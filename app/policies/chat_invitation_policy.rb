# frozen_string_literal: true

##
# ChatInvitationPolicy - Authorization for chat invitation actions
#
# Permissions:
# - Create/Cancel: Chat owner only
# - Show/Accept/Ignore: Invitee only (pending invitations)
#
class ChatInvitationPolicy < ApplicationPolicy
  ##
  # Only chat owner can create invitations.
  # The invitation must have a chat association.
  #
  def create?
    return false unless record.chat

    chat_owner?
  end

  def show?
    # Invitee can view their pending invitation
    pending_invitee?
  end

  def accept?
    # Invitee can accept pending invitation
    pending_invitee?
  end

  def ignore?
    # Invitee can ignore pending invitation
    pending_invitee?
  end

  def cancel?
    # Chat owner can cancel pending invitation
    record.status_pending? && chat_owner?
  end

  ##
  # Expose permissions as a hash for frontend consumption.
  #
  def to_h
    {
      "can_view" => show?,
      "can_accept" => accept?,
      "can_ignore" => ignore?,
      "can_cancel" => cancel?,
      "is_invitee" => invitee?,
      "is_chat_owner" => chat_owner?
    }
  end

  private

  def pending_invitee?
    record.status_pending? && invitee?
  end

  def invitee?
    record.invitee&.user == user
  end

  def chat_owner?
    record.chat&.member&.user == user
  end
end
