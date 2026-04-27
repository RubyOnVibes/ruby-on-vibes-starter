# frozen_string_literal: true

##
# ChatMember - Join table for multi-member chat access
#
# Enables:
# - Personal chats (single member = owner)
# - Team chats (multiple members)
# - Future: Chat invitations, role-based permissions
#
# Role hierarchy:
# - owner: Chat creator, can manage members and settings
# - member: Regular participant
#
class ChatMember < ApplicationRecord
  belongs_to :chat
  belongs_to :member
  
  # Simple integer enum - no meta-programming
  enum :role, {
    owner: 0,
    member: 1
  }, prefix: true
  
  validates :chat_id, uniqueness: { scope: :member_id }
  validates :role, presence: true
  validate :chat_must_have_owner, on: :update
  
  # Update chat's has_multiple_members flag when members change
  after_create :update_chat_multiple_members_flag
  after_destroy :update_chat_multiple_members_flag
  
  scope :for_chat, ->(chat) { where(chat: chat) }
  scope :for_member, ->(member) { where(member: member) }
  
  private
  
  ##
  # Validation: Chat must always have at least one owner
  # Prevents demoting the only owner to member
  #
  def chat_must_have_owner
    return unless role_changed? && !role_owner?
    
    # Check if this is the only owner
    other_owners = chat.chat_members.role_owner.where.not(id: id).exists?
    
    unless other_owners
      errors.add(:role, "cannot be changed - chat must have at least one owner")
    end
  end
  
  ##
  # Update chat's has_multiple_members flag based on member count
  # Called after create/destroy to keep flag in sync
  #
  def update_chat_multiple_members_flag
    # Count total members (including owner)
    member_count = chat.chat_members.count
    
    # Update flag: true if more than 1 member, false if only 1 (owner only)
    # Use update_column to skip callbacks and validations (performance)
    chat.update_column(:has_multiple_members, member_count > 1)
  end
end
