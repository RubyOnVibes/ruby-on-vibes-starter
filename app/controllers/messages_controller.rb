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

  MENTIONABLE_TYPES = %w[Chat Member Workspace].freeze
  
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
    
    @chat.with_lock do
      if @chat.chat_runs.active.exists? || @chat.running?
        respond_to do |format|
          format.turbo_stream { head :conflict }
          format.json { render json: { error: "Chat already processing" }, status: :conflict }
        end
        return
      end
      @message = @chat.messages.create!(role: :user, user_submitted: true,
        content: processed_content, user: current_user, member: current_member)
      uploaded_files.each { |file| @message.attachments.attach(file) }
      resolved_mentions.each { |mention| @message.mentions.create!(mentionable: mention.fetch(:record)) }
      @chat_run = @chat.chat_runs.create!(status: :pending,
        initiated_by_member: current_member, input_message: @message)
    end
    @message.reload.broadcast_append_to_chat
    @chat_run.dispatch!

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
  rescue ActiveRecord::RecordNotUnique
    respond_to do |format|
      format.turbo_stream { head :conflict }
      format.json { render json: { error: "Chat already processing" }, status: :conflict }
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
        Rails.logger.warn "[Mention] Skipped invalid mention for chat=#{@chat.id}"
        next
      end

      Rails.logger.info "[Mention] Processing: #{model_type}##{mentioned_id}"

      record = @chat.find_mentionable(type: model_type, id: mentioned_id, member: current_member)
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
      Rails.logger.error "[Mention] Resolution failed chat=#{@chat.id} error=#{e.class.name}"
      nil
    end
  end

  def normalize_mention_type(model_type)
    type = model_type.to_s.classify
    MENTIONABLE_TYPES.include?(type) ? type : nil
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
