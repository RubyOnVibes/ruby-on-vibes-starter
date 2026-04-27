# frozen_string_literal: true

##
# ChatInvitationsController - Manage all chat invitation actions
#
# Invitee: show, accept, ignore
# Inviter: create, destroy (cancel)
#
class ChatInvitationsController < ApplicationController
  before_action :set_invitation, except: [:create]
  
  def show
    return redirect_to chat_path(@chat_invitation.chat) if @chat_invitation.status_accepted?
    authorize @chat_invitation
    
    @chat = @chat_invitation.chat
    @inviter = @chat_invitation.inviter
  end
  
  def create
    chat_id = params[:chat_id]
    member_id = params[:member_id] || params[:invitee_member_id]

    @chat = if chat_id.to_s.start_with?('chat_')
      current_member.chats.find_by_prefix_id(chat_id)
    else
      current_member.chats.find_by(id: chat_id)
    end

    unless @chat
      render json: { error: 'Chat not found' }, status: :not_found
      return
    end

    # Build invitation to authorize (policy checks chat ownership)
    @chat_invitation = @chat.chat_invitations.build(inviter: current_member)
    authorize @chat_invitation

    @chat_invitation = @chat.invite_member(
      member_id: member_id,
      inviter: current_member
    )

    render json: {
      success: true,
      invitation_id: @chat_invitation.id,
      invitee_name: @chat_invitation.invitee.user.name
    }
  rescue ActiveRecord::RecordNotFound => e
    render json: { error: 'Member not found' }, status: :not_found
  rescue ActiveRecord::RecordInvalid => e
    render json: { error: e.record.errors.full_messages.join(', ') }, status: :unprocessable_entity
  end
  
  ##
  # DELETE /chat_invitations/:id
  # Cancel invitation (inviter only, pending only)
  #
  def destroy
    authorize @chat_invitation, :cancel?
    
    @chat_invitation.destroy
    
    respond_to do |format|
      format.html { redirect_to chat_path(@chat_invitation.chat), notice: "Invitation cancelled" }
      format.json { render json: { success: true } }
    end
  end
  
  def accept
    authorize @chat_invitation
    
    if @chat_invitation.accept!
      # Switch to the workspace of the invited member so we can access the chat
      session[:workspace_id] = @chat_invitation.invitee.workspace_id
      
      respond_to do |format|
        format.html { redirect_to chat_path(@chat_invitation.chat), notice: "Joined chat successfully" }
        format.json { render json: { success: true, chat_id: @chat_invitation.chat.to_param } }
      end
    else
      respond_to do |format|
        format.html { redirect_to chats_path, alert: "Failed to join chat" }
        format.json { render json: { error: 'Failed to accept invitation' }, status: :unprocessable_entity }
      end
    end
  end
  
  def ignore
    authorize @chat_invitation
    
    @chat_invitation.ignore!
    
    respond_to do |format|
      format.html { redirect_to chats_path, notice: "Invitation ignored" }
      format.json { render json: { success: true } }
    end
  end
  
  private
  
  def set_invitation
    invitation_id = params[:id]
    
    @chat_invitation = if invitation_id.to_s.start_with?('chatinv_')
      ChatInvitation.find_by_prefix_id(invitation_id)
    else
      ChatInvitation.find(invitation_id)
    end
    
    unless @chat_invitation
      respond_to do |format|
        format.html { redirect_to chats_path, alert: "Invitation not found" }
        format.json { render json: { error: 'Invitation not found' }, status: :not_found }
      end
    end
  rescue ActiveRecord::RecordNotFound
    respond_to do |format|
      format.html { redirect_to chats_path, alert: "Invitation not found" }
      format.json { render json: { error: 'Invitation not found' }, status: :not_found }
    end
  end
end
