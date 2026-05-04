# frozen_string_literal: true

##
# MessagesController - Handle message creation and streaming
#
# Dual format support:
# - Turbo Streams: For ERB/Islands (MutationObserver sync)
# - JSON + ActionCable: For Inertia (real-time sync)
#
class MessagesController < ApplicationController
  before_action :authenticate_user!
  before_action :set_chat, only: [:create]

  MENTIONABLE_RESOLVERS = {
    "Chat" => :resolve_chat_mention,
    "Member" => :resolve_member_mention,
    "Workspace" => :resolve_workspace_mention
  }.freeze
  
  # POST /messages
  # POST /chats/:chat_id/messages
  def create
    # Authorize: user must be a chat member to send messages
    authorize @chat, :send_messages?

    raw_content = params[:content].to_s.strip
    mentions_data = Array(params[:mentions])
    uploaded_files = params[:attachments] || []
    
    if raw_content.blank? && uploaded_files.empty?
      respond_to do |format|
        format.turbo_stream { head :unprocessable_content }
        format.json { render json: { error: 'Content or files required' }, status: :unprocessable_content }
      end
      return
    end

    resolved_mentions = resolve_mentions(mentions_data)
    
    # Substitute @mentions with stable placeholders
    # "Hey @Chat 2" → "Hey <@chat_2abc>"
    processed_content = substitute_mentions(raw_content, resolved_mentions)
    
    # Create user message using chat helper (ruby_llm method)
    # This will broadcast automatically via after_create_commit
    @message = @chat.messages.create!(
      role: :user, 
      user_submitted: true, 
      content: processed_content,
      user: current_user,  # Track which user sent the message
      member: current_member  # Track member context (includes org)
    )
    
    # Attach uploaded files (Active Storage)
    # ruby_llm will automatically include these in the LLM request via MessageMethods#extract_content
    if uploaded_files.any?
      uploaded_files.each do |file|
        @message.attachments.attach(file)
      end
      Rails.logger.info "[Message] Attached #{uploaded_files.size} file(s) to message #{@message.id}"
    end
    
    # Store mentions (polymorphic association via prefixed ID)
    Rails.logger.info "[Mention] Received mentions_data: #{mentions_data.inspect}"
    if resolved_mentions.any?
      resolved_mentions.each do |mention|
        # No label stored - always fetched fresh from mentionable.mentionable_label
        created_mention = @message.mentions.create!(
          mentionable: mention.fetch(:record)
        )
        Rails.logger.info "[Mention] Created: #{created_mention.inspect}"
      end
    end
    
    # Broadcast user message after mentions/attachments are added
    # CRITICAL: User messages skip after_create_commit broadcast, so we MUST broadcast here
    # Use append (not replace) since message not in DOM yet
    @message.reload
    @message.broadcast_append_to_chat
    
    # Create ChatRun BEFORE queuing job (status: pending)
    # Job will transition to :running when it starts
    # Unique index ensures only ONE active run per chat at a time
    #
    # Safety net: Expire any stale active runs left by crashed inline jobs.
    # With async_job (in-process), a server restart kills jobs without
    # running rescue blocks, leaving ChatRuns stuck in pending/running.
    # Without this cleanup, the unique index causes perpetual 409s.
    #
    # Uses update_all (not cancel!) because this must be bulletproof.
    # cancel! is heavy (transaction, message queries, tool call destruction)
    # and could itself raise if the crash left weird DB state.
    # recover_from_tool_errors! in ChatStreamJob already handles orphaned
    # tool chains, so cancel!'s cleanup work is redundant here.
    stale_runs = @chat.chat_runs.active
    if stale_runs.any?
      Rails.logger.warn "[MessagesController] ♻️ Expiring #{stale_runs.count} stale ChatRun(s) for chat #{@chat.id}"
      stale_runs.update_all(status: :failed, failed_at: Time.current)
    end

    Rails.logger.info "[MessagesController] 🎬 Creating ChatRun for chat #{@chat.id}"
    begin
      @chat_run = @chat.chat_runs.create!(status: :pending)
      Rails.logger.info "[MessagesController] ✅ ChatRun created: ID=#{@chat_run.id}, status=#{@chat_run.status}"
    rescue ActiveRecord::RecordNotUnique => e
      # Duplicate detected (chat already processing) - fail gracefully
      Rails.logger.warn "[MessagesController] ⚠️ Duplicate ChatRun detected: #{e.message}"
      respond_to do |format|
        format.turbo_stream { head :conflict }
        format.json { render json: { error: 'Chat already processing' }, status: :conflict }
      end
      return
    end
    
    # Queue AI response job (passes chat_run_id for atomicity)
    # MUST use perform_later (not perform_now) so after_commit broadcasts fire!
    ChatStreamJob.perform_later(@chat.id, @message.id, @chat_run.id)
    
    respond_to do |format|
      format.turbo_stream do
        # Turbo will append the new message via broadcast
        head :ok
      end
      
      format.json do
        render json: {
          success: true,
          message_id: @message.id,
          chat_run_id: @chat_run.id,
          message: @message.as_json_for_cable  # Full message data with mentions
        }, status: :ok
      end
    end
  end
  
  private
  
  def set_chat
    chat_id = params[:chat_id] || params[:message]&.[](:chat_id)
    
    # Handle both prefixed IDs (chat_xxx) and numeric IDs for backwards compatibility
    @chat = if chat_id.to_s.start_with?('chat_')
      current_member.chats.find_by_prefix_id(chat_id)
    else
      current_member.chats.find_by(id: chat_id)
    end
    
    unless @chat
      respond_to do |format|
        format.turbo_stream { head :not_found }
        format.json { render json: { error: 'Chat not found' }, status: :not_found }
      end
    end
  end

  def resolve_mentions(mentions_data)
    mentions_data.filter_map do |mention|
      mentioned_id = mention[:id] || mention['id']
      model_type = normalize_mention_type(mention[:model] || mention['model'])
      label = mention[:label] || mention['label']

      unless model_type && mentioned_id.present?
        Rails.logger.warn "[Mention] Skipped unknown mention type: #{mention.inspect}"
        next
      end

      Rails.logger.info "[Mention] Processing: #{model_type}##{mentioned_id}"

      record = send(MENTIONABLE_RESOLVERS.fetch(model_type), mentioned_id)
      unless record
        Rails.logger.warn "[Mention] Could not resolve in scope: #{model_type}##{mentioned_id}"
        next
      end

      {
        id: record.to_param,
        model: model_type,
        label: label.presence || record.mentionable_label,
        record: record
      }
    rescue StandardError => e
      Rails.logger.error "[Mention] Failed to resolve mention: #{e.message}"
      Rails.logger.error e.backtrace.first(5).join("\n")
      nil
    end
  end

  def normalize_mention_type(model_type)
    type = model_type.to_s.classify
    MENTIONABLE_RESOLVERS.key?(type) ? type : nil
  end

  def resolve_chat_mention(mentioned_id)
    find_scoped_mention(current_member.chats, mentioned_id)
  end

  def resolve_member_mention(mentioned_id)
    return unless @chat

    find_scoped_mention(@chat.members, mentioned_id)
  end

  def resolve_workspace_mention(mentioned_id)
    scope = if @chat
      Workspace.where(id: @chat.members.select(:workspace_id))
    else
      current_user.workspaces
    end

    find_scoped_mention(scope, mentioned_id)
  end

  def find_scoped_mention(scope, mentioned_id)
    return if mentioned_id.blank?

    if mentioned_id.to_s.include?('_') && scope.klass.respond_to?(:find_by_prefix_id)
      record = scope.klass.find_by_prefix_id(mentioned_id)
      return record if record && scope.exists?(id: record.id)
    else
      return scope.find_by(id: mentioned_id)
    end

    nil
  end
  
  ##
  # Substitute display labels with stable ID placeholders
  # "Hey @Chat 2" → "Hey <@chat_xxx>"
  #
  # Why stable IDs?
  # - Token efficient (8 chars: chat_4dA vs full 28 chars)
  # - Human/LLM readable
  # - Future-proof (name can change, ID won't)
  #
  def substitute_mentions(content, mentions_data)
    result = content.dup
    
    mentions_data.each do |mention|
      label = mention[:label] || mention['label']
      stable_id = mention[:id] || mention['id']  # Now just :id, not nested
      
      next unless label.present? && stable_id.present?
      
      # Replace "@Chat 2" with "<@chat_xxx>"
      # Angle brackets prevent collisions with plain text
      result.gsub!(/@#{Regexp.escape(label)}/, "<@#{stable_id}>")
    end
    
    result
  end
  
end
