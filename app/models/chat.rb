class Chat < ApplicationRecord
  has_many :example_report_publications, class_name: "Examples::ReportPublication", inverse_of: :chat, dependent: :destroy
  has_prefix_id :chat
  include Mentionable

  acts_as_chat

  # Runtime-only actor for record hydration. Set by ChatPurpose, never Current.
  attr_accessor :llm_context_member

  validates :purpose, inclusion: { in: ->(_) { ChatPurpose.keys } }
  validate :purpose_is_fixed_during_work

  # Filter messages before sending to LLM API.
  #
  # Excludes:
  # - Messages explicitly excluded from context
  # - Empty placeholders with no native replay state
  #
  # Preserves:
  # - Assistant messages with tool_calls (even if text content is blank)
  # - Tool result messages (orphaning them causes API errors)
  # - Native provider state, reasoning and attachments even without visible text
  def order_messages_for_llm(messages)
    filtered = messages.reject do |msg|
      next true if msg.skip_llm_context?
      next true if msg.compacted?
      next false if msg.role.to_s == "system"
      next false if msg.content.present?
      next false if msg.llm_replay_payload?
      # Native terminal answers can be empty (for example, a filtered reply).
      # A finish marker or recorded input distinguishes them from placeholders.
      next false if msg.role.to_s == "assistant" && (msg.finish_reason.present? || !msg.tokens.input.nil?)
      next false if msg.role.to_s == "tool"
      next false if msg.role.to_s == "assistant" && msg.ruby_llm_tool_calls.exists?
      true
    end

    filtered
  end

  # Filter the loaded transcript without interpreting native provider blocks.
  # Keep this adapter covered by native persistence/replay tests on upgrades.
  def eager_load_messages
    records = order_messages_for_llm(super)
    users = records.select { |message| message.role == "user" }
    users.each do |message|
      message.llm_context_summary = nil
      message.llm_context_member = llm_context_member
    end
    users.first.llm_context_summary = compaction_summary if users.any?
    records
  end
  private :eager_load_messages

  belongs_to :member  # Creator/owner (for audit trail and permissions)
  has_many :messages, dependent: :destroy  # Cascade delete all messages when chat deleted
  has_many :chat_runs, dependent: :destroy  # Track job executions for cancellation
  has_many :agent_deliveries, dependent: :destroy, inverse_of: :chat
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

  # Shared mention policy for admission and later model hydration. Participation
  # grants member/workspace context across a group chat, but another chat must
  # still be accessible to the current actor. New types require explicit policy.
  def mentionable_scope(type, member:)
    return unless member && members.exists?(id: member.id)

    case type.to_s
    when "Member" then members
    when "Workspace" then Workspace.where(id: members.select(:workspace_id))
    when "Chat" then member.chats
    end
  end

  def find_mentionable(type:, id:, member:)
    return unless id.is_a?(String) || id.is_a?(Integer)
    return if id.blank?

    scope = mentionable_scope(type, member: member)
    return unless scope

    id.to_s.include?("_") ? scope.find_by_prefix_id(id) : scope.find_by(id: id)
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
    invitee = if member_id.to_s.start_with?("mbr_")
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

  def purpose_is_fixed_during_work
    if persisted? && will_save_change_to_purpose? && (chat_runs.active.exists? || pending_tasks.any? || pending_questions.any?)
      errors.add(:purpose, "cannot change while work is pending")
    end
  end

  def generate_name_from_timestamp
    return if name.present?

    # Generate human-readable timestamp: "Chat Nov 27 3:45pm"
    time = Time.current.in_time_zone(member.user.time_zone || "UTC")
    timestamp = time.strftime("%b %d %l:%M%P").gsub(/\s+/, " ").strip
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
