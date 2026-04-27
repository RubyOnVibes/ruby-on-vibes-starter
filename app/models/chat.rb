class Chat < ApplicationRecord
  has_prefix_id :chat
  include Mentionable

  acts_as_chat

  # Filter messages before sending to LLM API.
  #
  # Excludes:
  # - Messages marked skip_llm_context (from recover_from_tool_errors!)
  # - Empty non-system messages from cancelled ChatRuns
  #
  # Preserves:
  # - Assistant messages with tool_calls (even if text content is blank)
  # - Tool result messages (orphaning them causes API errors)
  def order_messages_for_llm(messages)
    filtered = messages.reject do |msg|
      next true if msg.skip_llm_context?
      next true if msg.compacted?
      next false if msg.role.to_s == 'system'
      next false if msg.content.present?
      next false if msg.role.to_s == 'tool'
      next false if msg.role.to_s == 'assistant' && msg.tool_calls.exists?
      true
    end

    # Deduplicate consecutive user messages. These occur when RubyLLM's
    # cleanup_failed_messages destroys the assistant placeholder on API error,
    # leaving user messages with no response between them. The Anthropic API
    # rejects consecutive same-role messages. Keep only the last in each run.
    deduped = []
    filtered.each do |msg|
      if msg.role.to_s == 'user' && deduped.last&.role.to_s == 'user'
        deduped[-1] = msg
      else
        deduped << msg
      end
    end

    super(deduped)
  end

  ##
  # Recover from incomplete tool call chains left by crashed processes.
  #
  # When a process dies mid-tool-execution (server restart, OOM, deploy),
  # no Ruby rescue runs and RubyLLM's cleanup_orphaned_tool_results never
  # fires. This leaves partial tool chains in the DB:
  #
  #   [assistant: tool_use(A) + tool_use(B)]  ← expects 2 results
  #   [tool: result_for_A]                     ← only 1 arrived
  #
  # The Anthropic API rejects incomplete chains. Without recovery, every
  # subsequent message in the chat fails — the chat is permanently broken.
  #
  # This method marks broken chains as skip_llm_context: true (preserving
  # them for audit trail) so the LLM never sees them.
  #
  # Common with async_job adapter where jobs run in-process and die with
  # the server. Less common with SolidQueue/Sidekiq (separate workers).
  #
  def recover_from_tool_errors!
    recovered = false

    # Pass 1: Assistant messages with incomplete tool chains
    self.messages.where(role: 'assistant', skip_llm_context: false)
        .joins(:tool_calls)
        .distinct
        .each do |assistant_msg|
      tool_call_db_ids = assistant_msg.tool_calls.pluck(:id)
      expected_count = tool_call_db_ids.size
      actual_count = self.messages.where(role: 'tool', tool_call_id: tool_call_db_ids).count

      next if actual_count == expected_count

      assistant_msg.update_columns(skip_llm_context: true)
      self.messages.where(role: 'tool', tool_call_id: tool_call_db_ids)
          .update_all(skip_llm_context: true)

      # Also mark the triggering user message
      prev_msg = self.messages.where('id < ?', assistant_msg.id).order(id: :desc).first
      if prev_msg && prev_msg.role == 'user'
        prev_msg.update_columns(skip_llm_context: true)
        Rails.logger.info "[Chat##{id}] Also marked triggering user message #{prev_msg.id} as skip_llm_context"
      end

      recovered = true
      Rails.logger.warn "[Chat##{id}] Recovered incomplete tool chain: " \
        "msg #{assistant_msg.id} (#{actual_count}/#{expected_count} results)"
    end

    # Pass 2: Orphaned tool result messages (parent_tool_call was destroyed,
    # e.g. by ChatRun cancel cleanup, leaving tool_call_id = nil)
    orphaned = self.messages.where(role: 'tool', tool_call_id: nil, skip_llm_context: false)
    if orphaned.exists?
      count = orphaned.update_all(skip_llm_context: true)
      recovered = true
      Rails.logger.warn "[Chat##{id}] Marked #{count} orphaned tool result messages as skip_llm_context"
    end

    # Pass 3: Tool messages whose parent assistant is filtered
    cleanup_orphaned_tool_messages!

    recovered
  end

  belongs_to :member  # Creator/owner (for audit trail and permissions)
  has_many :messages, dependent: :destroy  # Cascade delete all messages when chat deleted
  has_many :chat_runs, dependent: :destroy  # Track job executions for cancellation
  has_many :agent_tasks, dependent: :destroy  # Background tasks triggered through chat
  has_one :agent  # Optional: if this chat belongs to a persistent agent

  ##
  # Does this chat belong to a persistent agent?
  #
  def agent?
    agent.present?
  end

  # Multi-member support
  has_many :chat_members, dependent: :destroy
  has_many :members, through: :chat_members  # All participants (including owner)
  has_many :chat_invitations, dependent: :destroy  # Pending invitations

  # Ensure creator is added as owner member on creation
  after_create :add_creator_as_owner

  # Validate owner exists in chat_members
  validate :owner_must_be_chat_member, on: :update, if: :member_id_changed?
  
  # Scopes for filtering by member count
  scope :personal, -> { where(has_multiple_members: false) }
  scope :with_multiple_members, -> { where(has_multiple_members: true) }
  
  def self.show_tool_calls_in_ui?
    true  # Default: show tool calls
  end
  
  # Convenience accessors
  def user
    member.user
  end
  
  def workspace
    member.workspace
  end
  
  ##
  # Authorization helpers
  #
  def owner?(m)
    member_id == m.id
  end
  
  def member_exists?(m)
    chat_members.exists?(member_id: m.id)
  end
  
  def admin?(m)
    owner?(m)  # For now, only owner is admin
  end
  
  ##
  # Chat type helpers
  #
  def personal?
    !has_multiple_members
  end
  
  def group?
    has_multiple_members
  end
  
  ##
  # Get the owner ChatMember record
  #
  def owner_chat_member
    chat_members.role_owner.first
  end
  
  ##
  # Invite a member to this chat
  # Accepts member prefix_id (mbr_xxx) or numeric ID
  #
  # @param member_id [String, Integer] Member prefix_id or ID
  # @param inviter [Member] Member sending the invitation
  # @return [ChatInvitation] The created invitation
  #
  def invite_member(member_id:, inviter:)
    invitee = if member_id.to_s.start_with?('mbr_')
      Member.find_by_prefix_id(member_id)
    else
      Member.find(member_id)
    end
    
    raise ActiveRecord::RecordNotFound, "Member #{member_id} not found" unless invitee
    
    chat_invitations.create!(
      invitee: invitee,
      inviter: inviter
    )
  end
  
  ##
  # Check if member has a pending invitation
  #
  def pending_invitation_for?(member)
    chat_invitations.status_pending.exists?(invitee: member)
  end
  
  # Override mentionable_label
  def mentionable_label
    name.presence || "Chat ##{id}"
  end
  
  ##
  # LLM-friendly summary
  # Keep concise for token efficiency (aim for <20 tokens)
  #
  def mentionable_summary
    parts = []
    parts << "titled '#{name}'" if name.present?
    parts << "#{messages.count} messages"
    
    "Chat #{parts.join(', ')}"
  end
  
  # Auto-generate name with timestamp
  before_validation :generate_name_from_timestamp, if: -> { name.blank? }, on: :create
  
  private
  
  ##
  # Pass 3: Tool messages whose parent assistant message is filtered out.
  #
  # After Pass 1 marks an assistant message as skip_llm_context, its tool
  # result messages may still be in the LLM context. The API sees tool_result
  # without a matching tool_use → 400 error.
  #
  def cleanup_orphaned_tool_messages!
    self.messages.where(role: 'tool', skip_llm_context: false).find_each do |tool_msg|
      next unless tool_msg.tool_call_id

      tool_call_record = tool_msg.parent_tool_call
      unless tool_call_record
        # tool_call_id is set but record is gone (destroyed by cancel!)
        tool_msg.update_column(:skip_llm_context, true)
        Rails.logger.warn "[Chat##{id}] Tool message #{tool_msg.id} orphaned (ToolCall destroyed)."
        next
      end

      parent_assistant = tool_call_record.message
      next unless parent_assistant

      # If parent assistant is filtered (skipped, or empty without tool_calls),
      # this tool msg is orphaned. Assistant messages with tool_calls legitimately
      # have empty content — that's normal, not filtered.
      parent_filtered = parent_assistant.skip_llm_context? ||
                        (parent_assistant.content.to_s.strip.empty? && !parent_assistant.tool_calls.exists?)

      if parent_filtered
        Rails.logger.warn "[Chat##{id}] Tool message #{tool_msg.id} orphaned " \
          "(parent assistant #{parent_assistant.id} is filtered). Marking as skip_llm_context."
        tool_msg.update_column(:skip_llm_context, true)
      end
    end
  end

  def generate_name_from_timestamp
    return if name.present?
    
    # Generate human-readable timestamp: "Chat Nov 27 3:45pm"
    time = Time.current.in_time_zone(member.user.time_zone || 'UTC')
    timestamp = time.strftime("%b %d %l:%M%P").gsub(/\s+/, ' ').strip
    self.name = "Chat #{timestamp}"
  end
  
  ##
  # Callback: Add creator as owner in chat_members on creation
  # This ensures the owner is always a participant
  #
  def add_creator_as_owner
    return unless member_id.present?
    
    owner_chat_member
  rescue ActiveRecord::RecordInvalid => e
    # If owner already exists (e.g., from backfill), ignore
    Rails.logger.debug "[Chat] Owner already exists for chat #{id}: #{e.message}"
  end

  def owner_chat_member
    return unless member_id.present?
    
    chat_members.find_or_create_by!(
      member_id: member_id,
      role: :owner
    )
  end
  
  ##
  # Validation: Owner must exist in chat_members
  # Prevents orphaning a chat by changing member_id to someone not in members
  #
  def owner_must_be_chat_member
    return unless persisted? && member_id.present?
    
    unless chat_members.exists?(member_id: member_id)
      errors.add(:member_id, "must be a chat member")
    end
  end
end