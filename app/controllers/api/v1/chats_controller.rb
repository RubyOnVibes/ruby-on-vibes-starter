# frozen_string_literal: true

module Api
  module V1
    ##
    # ChatsController - API for chat-related data
    #
    class ChatsController < Api::V1::BaseController
      before_action :authenticate_user!
      before_action :set_chat
      
      ##
      # GET /api/v1/chats/:id/pending_invitations
      # List pending invitations for a chat (owner only)
      #
      def pending_invitations
        unless @chat.owner?(current_member)
          render json: { error: 'Forbidden' }, status: :forbidden
          return
        end
        
        @invitations = @chat.chat_invitations
          .status_pending
          .includes(invitee: [:user, :workspace])
          .order(created_at: :desc)
        
        render json: @invitations.map { |inv| serialize_invitation(inv) }
      end
      
      private
      
      def set_chat
        chat_id = params[:id] || params[:chat_id]
        
        @chat = if chat_id.to_s.start_with?('chat_')
          current_member.chats.find_by_prefix_id(chat_id)
        else
          current_member.chats.find_by(id: chat_id)
        end
        
        unless @chat
          render json: { error: 'Chat not found' }, status: :not_found
        end
      end
      
      def serialize_invitation(inv)
        {
          id: inv.id,
          inviteeId: inv.invitee.to_param,
          inviteeName: inv.invitee.user.name,
          inviteeOrgName: inv.invitee.workspace.name,
          inviteeOrgType: inv.invitee.workspace.personal? ? 'Personal' : 'Team',
          status: inv.status,
          createdAt: inv.created_at.iso8601
        }
      end
    end
  end
end
