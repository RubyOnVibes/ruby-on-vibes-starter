# frozen_string_literal: true

##
# ChatInvitation - Member-to-member chat sharing
#
# Architecture:
# - Member-based (not email-based) - invites existing users only
# - Cross-org by default (personal + team members can collaborate)
# - Noticed notifications (in-app, no email spam)
# - Explicit accept/ignore (no auto-add)
#
# Status flow: pending → (accepted | ignored)
#
class ChatInvitation < ApplicationRecord
  has_prefix_id :chatinv
  
  belongs_to :chat
  belongs_to :inviter, class_name: 'Member'
  belongs_to :invitee, class_name: 'Member'
  
  enum :status, {
    pending: 0,
    accepted: 1,
    ignored: 2
  }, prefix: true
  
  validate :cannot_invite_existing_member, on: :create
  validate :cannot_invite_self, on: :create
  validate :cannot_have_pending_invitation, on: :create
  
  # Send Noticed notification when invitation created
  after_create :send_notification
  
  scope :for_chat, ->(chat) { where(chat: chat) }
  scope :for_member, ->(member) { where(invitee: member) }
  
  def accept!
    transaction do
      chat.chat_members.create!(member: invitee, role: :member)
      update!(status: :accepted, responded_at: Time.current)
      
      chat.messages.create!(
        role: 'assistant',
        content: "#{invitee.user.name} joined the chat",
        user_submitted: false,
        metadata: { system_event: 'member_joined', member_name: invitee.user.name }
      )
    end
    
    true
  rescue ActiveRecord::RecordInvalid => e
    Rails.logger.error "[ChatInvitation] Accept failed: #{e.message}"
    false
  end
  
  def ignore!
    update!(status: :ignored, responded_at: Time.current)
  end
  
  private
  
  def cannot_invite_existing_member
    return unless chat_id.present? && invitee_id.present?
    
    if chat.chat_members.exists?(member_id: invitee_id)
      errors.add(:invitee, "is already a member of this chat")
    end
  end
  
  def cannot_invite_self
    if inviter_id.present? && inviter_id == invitee_id
      errors.add(:invitee, "cannot invite yourself")
    end
  end
  
  def cannot_have_pending_invitation
    return unless chat_id.present? && invitee_id.present?
    
    if chat.chat_invitations.status_pending.exists?(invitee_id: invitee_id)
      errors.add(:invitee, "has already been invited to this chat. You can cancel the existing invitation below.")
    elsif chat.chat_invitations.status_accepted.exists?(invitee_id: invitee_id)
      errors.add(:invitee, "has already accepted an invitation to this chat")
    end
  end
  
  def send_notification
    ChatInvitationNotifier.with(
      invitation_id: prefix_id,
      chat_name: chat.name,
      inviter_name: inviter.user.name
    ).deliver(invitee.user)
  end
end
