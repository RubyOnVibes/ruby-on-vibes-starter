# frozen_string_literal: true

##
# Chats::MembersController - Manage chat members
#
# List members in a chat
# Remove members from a chat (owner only)
#
class Chats::MembersController < ApplicationController
  before_action :authenticate_user!
  before_action :set_chat
  
  ##
  # GET /chats/:chat_id/members
  # List all members in the chat with org context
  #
  def index
    # Any chat member can view members list
    authorize @chat, :show?

    @members = @chat.chat_members
      .includes(member: [:user, :workspace])
      .order(created_at: :asc)

    render json: @members.map { |cm| serialize_chat_member(cm) }
  end

  ##
  # DELETE /chats/:chat_id/members/:id
  # Remove a member from the chat (owner only, can't remove self)
  #
  def destroy
    authorize @chat, :manage_members?

    @chat_member = @chat.chat_members.find(params[:id])

    # Can't remove owner (policy-level check would be better, but this is explicit)
    if @chat_member.role_owner?
      render json: { error: 'Cannot remove chat owner' }, status: :forbidden
      return
    end

    @chat_member.destroy

    render json: { success: true }
  end
  
  private
  
  def set_chat
    @chat = current_member.chats.find_by_prefix_id(params[:chat_id])
    
    unless @chat
      render json: { error: 'Chat not found' }, status: :not_found
    end
  end
  
  def serialize_chat_member(cm)
    {
      id: cm.id,
      memberId: cm.member.to_param,
      userName: cm.member.user.name,
      userAvatar: cm.member.user.avatar_url,
      orgId: cm.member.workspace.to_param,
      orgName: cm.member.workspace.name,
      orgType: cm.member.workspace.personal? ? 'Personal' : 'Team',
      role: cm.role,
      isOwner: cm.role_owner?,
      joinedAt: cm.created_at.iso8601
    }
  end
end
