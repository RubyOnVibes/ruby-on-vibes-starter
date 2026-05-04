# frozen_string_literal: true

##
# ChatInvitationNotifier - In-app notifications for chat invitations
#
# Delivers instant notifications when member is invited to a chat.
# No email delivery - keeps it simple and fast.
#
# Usage:
#   ChatInvitationNotifier.with(
#     invitation_id: invitation.id,
#     chat_name: chat.name,
#     inviter_name: inviter.user.name
#   ).deliver(invitee.user)
#
class ChatInvitationNotifier < ApplicationNotifier
  # In-app only (no email). Notifications auto-persist to the database;
  # no `deliver_by :database` needed (and it's deprecated as of Noticed 2.x).

  notification_methods do
    def message
      inviter_name = params[:inviter_name] || 'Someone'
      chat_name = params[:chat_name] || 'a chat'
      "#{inviter_name} invited you to join '#{chat_name}'"
    end
    
    def url
      invitation_id = params[:invitation_id]
      return "/chats" unless invitation_id
      
      Rails.application.routes.url_helpers.chat_invitation_path(id: invitation_id)
    end
    
    def title
      "Chat Invitation"
    end

    def icon
      "💬"
    end
  end
end
