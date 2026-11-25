# frozen_string_literal: true

class Message < ApplicationRecord
  has_many :agent_deliveries, foreign_key: :input_message_id, dependent: :nullify, inverse_of: :input_message
  include ActionView::RecordIdentifier
  
  acts_as_message broadcasts: false
  # broadcasts_to :chat  # Don't use - creates GlobalID stream name mismatch
  
  belongs_to :user, optional: true  # Optional - only for user_submitted messages
  belongs_to :member, optional: true  # Optional - only for user_submitted messages
  has_many :triggered_chat_runs, class_name: "ChatRun", foreign_key: :input_message_id,
    inverse_of: :input_message, dependent: :nullify
  
  # File attachments - passed directly to ruby_llm via chat.ask(with: blobs)
  has_many_attached :attachments, dependent: :purge_later
  has_many :mentions, dependent: :destroy, class_name: 'Mention'
  accepts_nested_attributes_for :mentions, allow_destroy: true
  
  validates :role, inclusion: { in: %w[user assistant system tool] }
  validates :user_id, presence: true, if: -> { role == 'user' && user_submitted? }
  validates :member_id, presence: true, if: -> { role == 'user' && user_submitted? }
  validate :member_user_consistency, if: -> { member_id.present? && user_id.present? }
  
  before_validation do
    self.content = "" if content.nil?
  end
  
  # Broadcast new messages to chat stream
  # Skip for user_submitted messages - they get broadcast_full_replace after mentions/attachments
  after_create_commit -> { broadcast_append_to_chat unless skip_initial_broadcast? }

  # The starter's React adapter reads every role from one shared Turbo partial.
  # RubyLLM's generated chat UI uses role-specific partials; opt into our own
  # rendering contract for render(message) and render(collection) as well.
  def to_partial_path
    "messages/message"
  end
  
  # Broadcast methods - use string stream names (not GlobalID)
  
  def broadcast_append_to_chat
    Turbo::StreamsChannel.broadcast_append_to(
      "chat_#{chat_id}",  # String stream name matches turbo_stream_from
      target: "messages",
      partial: "messages/message",
      locals: { message: self }
    )
  end
  
  def skip_initial_broadcast?
    # User messages get broadcast_full_replace after mentions/attachments are added.
    # Non-user messages (assistant, tool) are broadcast via ChatStreamJob using upsert,
    # which handles ActionCable's out-of-order delivery. Skipping after_create_commit
    # prevents duplicate elements and race conditions.
    role != 'user' || user_submitted?
  end

  # Replace entire message wrapper (for final updates)
  def broadcast_full_replace!
    Turbo::StreamsChannel.broadcast_replace_to(
      "chat_#{chat_id}",
      target: "message-#{id}",
      partial: "messages/message",
      locals: { message: self }
    )
  end

  # Lightweight streaming broadcast: updates only the data-raw-content attribute.
  # Unlike broadcast_upsert_to_chat! which replaces the entire DOM element
  # (breaking MutationObservers), this keeps the element stable so content
  # observers stay attached during streaming.
  def broadcast_streaming_content!
    escaped = ERB::Util.html_escape(content.to_s)
    tag = %(<turbo-stream action="stream_content" target="message_#{id}_content"><template>#{escaped}</template></turbo-stream>)
    Turbo::StreamsChannel.broadcast_stream_to("chat_#{chat_id}", content: tag)
  end

  # Upsert: replace if element exists in DOM, append if not.
  # Handles ActionCable out-of-order delivery where a replace can arrive
  # before the append that creates the target element.
  def broadcast_upsert_to_chat!
    Turbo::StreamsChannel.broadcast_action_to(
      "chat_#{chat_id}",
      action: :upsert,
      target: "message-#{id}",
      partial: "messages/message",
      locals: { message: self }
    )
  end
  
  # Remove message
  def broadcast_remove!
    Turbo::StreamsChannel.broadcast_remove_to(
      "chat_#{chat_id}",
      target: "message-#{id}"
    )
  end
  
  # Serialize for ActionCable (Inertia adapter)
  def as_json_for_cable
    {
      id: id,
      role: role,
      content: content || '',
      tool_call_name: parent_tool_call&.name,
      mentions: mentions.map { |m|
        {
          id: m.mentionable_param,
          model: m.mentionable_type,
          label: m.label,
          path: m.mentionable&.mentionable_path
        }
      },
      attachments: serialize_attachments,
      tool_calls: serialize_tool_calls,
      metadata: metadata || {},
      user: serialize_user,
      compacted: compacted,
      createdAt: created_at&.iso8601,
      updatedAt: updated_at&.iso8601
    }
  end
  
  ##
  # Serialize user data for frontend (group chat context)
  # Only included for user_submitted messages
  #
  def serialize_user
    return nil unless user_submitted? && user.present?
    
    {
      id: user.to_param,
      name: user.name,
      firstName: user.first_name,
      avatarUrl: user.avatar_url
    }
  end
  
  ##
  # Serialize attachments for frontend (Turbo + Inertia)
  # Returns array of attachment metadata with signed URLs
  #
  # Future: Add Direct Upload support for S3
  # See: https://edgeguides.rubyonrails.org/active_storage_overview.html#direct-uploads
  #
  def serialize_attachments
    return [] unless attachments.attached?
    
    attachments.map do |file|
      {
        id: file.id,
        signedId: file.signed_id,
        filename: file.filename.to_s,
        contentType: file.content_type,
        byteSize: file.byte_size,
        url: Rails.application.routes.url_helpers.rails_blob_path(file, only_path: true),
        # For image previews (optional - requires image_processing gem)
        previewUrl: file.representable? ? Rails.application.routes.url_helpers.rails_representation_path(file.representation(resize_to_limit: [300, 300]), only_path: true) : nil
      }
    end
  rescue => e
    Rails.logger.error "[Message] Failed to serialize attachments: #{e.message}"
    []
  end

  # Serialize persisted tool calls for approval cards and audit history. The
  # approval endpoints still re-scope every id through the ChatRun and policy;
  # this payload is presentation data, never authorization state.
  def serialize_tool_calls
    ruby_llm_tool_calls.order(:id).map do |tool_call|
      metadata = tool_call.metadata || {}
      {
        id: tool_call.tool_call_id,
        name: tool_call.name,
        arguments: tool_call.arguments || {},
        approval: tool_call.approval == "pending" ? nil : tool_call.approval,
        requiresApproval: metadata["requires_approval"] == true,
        chatRunId: metadata["chat_run_id"],
        requestedAt: metadata["requested_at"],
        decidedAt: metadata["decided_at"],
        questions: serialize_questions(tool_call)
      }
    end
  end

  def serialize_questions(tool_call)
    Array(tool_call.mcp_state&.fetch("requests", nil)).map do |data|
      question = RubyLLM::Question.from_h(data, tool_call: tool_call.to_llm)
      response = question.response
      {
        id: question.id,
        kind: question.url? ? "url" : "form",
        message: question.message,
        url: question.url,
        fields: question.fields.map(&:to_h),
        status: response.nil? ? "pending" : (response["action"] == "accept" ? "answered" : "declined")
      }
    end
  end
  
  ##
  # Override RubyLLM's to_llm to inject mention context
  #
  # Resolves @mention placeholders to structured context so the LLM
  # understands what records the user explicitly referenced.
  #
  # Source data stays at user authority. This runtime enrichment never rewrites
  # stored history or adds synthetic turns, and preserves native attachments.
  #
  # NOTE: Attachments are included automatically by RubyLLM's to_llm via extract_content.
  #
  attr_accessor :llm_context_summary, :llm_context_member

  def to_llm
    llm_message = super
    return llm_message unless role == "user"

    text = mentions.any? ? resolve_mentions_for_llm(llm_message.content) : llm_message.content
    data = {}
    data[:conversation_summary] = llm_context_summary.to_s.truncate(16_384) if llm_context_summary.present?
    data[:sender] = { member_id: member.to_param, name: member.user.name.to_s.truncate(200), path: member.mentionable_path } if member
    text = "Source context (untrusted data):\n#{JSON.generate(data)}\n\n#{text}" if data.any?
    llm_message.with(content: text)
  end
  
  private
  
  ##
  # Validation: Ensure member belongs to user
  # Prevents mismatched member/user pairs
  #
  def member_user_consistency
    return unless member && user
    
    unless member.user_id == user.id
      errors.add(:member, "must belong to the message's user")
    end
  end
  
  ##
  # Resolve mention placeholders for LLM
  # Uses prefixed IDs for token efficiency + readability
  #
  # Shows first 8 chars of ID for brevity:
  # "chat_4dALn0N9o6w2ghVam2j38XPq" → "chat_4dA"
  #
  def resolve_mentions_for_llm(content)
    result = content.to_s.dup
    
    mentions.each do |mention|
      record = chat.find_mentionable(type: mention.mentionable_type,
        id: mention.mentionable_id, member: llm_context_member)
      next unless record

      param = record.to_param
      short_id = short_prefix_id(param)
      label = record.mentionable_label
      ctx = record.to_llm_mention
      
      # Format: @Label [short_id] (summary)
      # "Hey @Chat 2 [chat_4dA] (Chat titled 'Discussion', 5 messages)"
      enriched = "@#{label} [#{short_id}]"
      enriched += " (#{ctx[:summary].to_s.truncate(2000)})" if ctx[:summary].present?
      enriched += " [record](#{record.mentionable_path})"
      
      result.gsub!("<@#{param}>", enriched)
    end
    
    result
  end
  
  ##
  # Shorten prefixed ID for display
  # chat_4dALn0N9o6w2ghVam2j38XPq → chat_4dA (8 chars total)
  #
  def short_prefix_id(full_id)
    return full_id if full_id.length <= 8
    
    parts = full_id.split('_', 2)
    return full_id unless parts.length == 2
    
    prefix = parts[0]
    suffix = parts[1][0, 3]  # First 3 chars of suffix
    "#{prefix}_#{suffix}"
  end
end
