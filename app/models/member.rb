class Member < ApplicationRecord
  has_prefix_id :mbr

  include Mentionable
  include Workspace::Roles

  belongs_to :workspace, counter_cache: true
  belongs_to :user
  
  # Chat associations - multi-member support
  has_many :owned_chats, class_name: 'Chat', foreign_key: 'member_id', dependent: :destroy
  has_many :chat_members, dependent: :destroy
  has_many :chats, through: :chat_members  # All chats this member can access
  
  # Chat invitations
  has_many :sent_chat_invitations, class_name: 'ChatInvitation', foreign_key: 'inviter_id', dependent: :destroy
  has_many :received_chat_invitations, class_name: 'ChatInvitation', foreign_key: 'invitee_id', dependent: :destroy
  
  ##
  # Get pending chat invitations for this member
  #
  def pending_chat_invitations
    received_chat_invitations.status_pending.includes(:chat, :inviter)
  end
  
  validates :workspace_id, uniqueness: { scope: :user_id }
  validate :owner_cannot_be_removed, on: :update

  def workspace_owner?
    return unless user

    workspace&.owner_id == user_id
  end
  
  ##
  # Mentionable label - just the user's name
  # Keep simple to avoid confusing LLM (no special chars like |)
  #
  def mentionable_label
    user.name.presence || user.username
  end
  
  ##
  # Brief summary for LLM context (multitenancy)
  #
  def mentionable_summary
    parts = []
    
    # User identity
    user_name = [user.first_name, user.last_name].join(' ').presence || user.email
    parts << "User: #{user_name}"
    
    # Workspace context
    parts << "Workspace: #{workspace.name}"
    
    # Roles
    roles_list = active_roles.map(&:to_s).join(', ')
    parts << "Roles: #{roles_list}" if roles_list.present?
    
    # Ownership
    parts << "Owner" if workspace_owner?
    
    "Member (#{parts.join(', ')})"
  end
  
  ##
  # Simple path for @mentions - /m/:id
  # Doesn't require workspace context in URL (looked up from member)
  #
  #
  def mentionable_path
    Rails.application.routes.url_helpers.member_path(self)
  end

  private

  def owner_cannot_be_removed
    return unless workspace&.owner_id == user_id && admin_changed?

    if ActiveRecord::Type::Boolean.new.cast(admin) == false
      errors.add(:admin, 'cannot be marked false for the workspace owner')
    end
  end
end