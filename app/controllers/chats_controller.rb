# frozen_string_literal: true

##
# ChatsController - Chat interface with IslandJS
#
# This template uses IslandJS for the chat interface (see app/javascript/islands/components/ChatIsland.jsx).
# For a full Inertia.js SPA implementation, you could create an Inertia page at app/javascript/pages/Chat/Show.jsx
# and conditionally render it based on request.inertia?.
#
class ChatsController < ApplicationController
  before_action :authenticate_user!
  before_action :require_chat_enabled!
  before_action :set_chat, only: [:show, :update, :destroy, :leave, :messages, :clear]
  
  def index
    # Idempotently provision default agents for the workspace
    AgentProvisioner.provision!(current_workspace) if current_workspace

    @chat = nil
    @messages = []
    @active_chat_run = nil
    @chat_permissions = {}
    @show_tool_calls = Chat.show_tool_calls_in_ui?

    render :show
  end
  
  def show
    authorize @chat
    
    @messages = @chat.messages
      .where("role != 'user' OR user_submitted = ?", true)
      .order(created_at: :asc)
    
    @active_chat_run = @chat.chat_runs.active.first
    @chat_permissions = policy(@chat).to_h
    @show_tool_calls = Chat.show_tool_calls_in_ui?
  end
  
  def create
    @chat = current_member.owned_chats.create!
    
    respond_to do |format|
      format.html { redirect_to chat_path(@chat) }
      format.json { render json: { id: @chat.to_param }, status: :created }
    end
  end
  
  def update
    authorize @chat
    
    if @chat.update(chat_params)
      render json: { id: @chat.to_param, name: @chat.name }, status: :ok
    else
      render json: { errors: @chat.errors }, status: :unprocessable_content
    end
  end
  
  def destroy
    authorize @chat
    
    @chat.destroy
    head :no_content
  end
  
  # JSON endpoint for client-side reconciliation after streaming
  def messages
    authorize @chat, :show?

    messages = @chat.messages
      .where("role != 'user' OR user_submitted = ?", true)
      .order(:id)
      .map(&:as_json_for_cable)

    render json: messages
  end

  def clear
    authorize @chat, :update?

    @chat.transaction do
      @chat.update!(agent_tasks_dismissed_at: Time.current, compaction_summary: nil, last_compacted_at: nil)

      message_ids = @chat.message_ids

      # Break circular FK: messages.tool_call_id → tool_calls
      @chat.messages.where.not(tool_call_id: nil).update_all(tool_call_id: nil)

      # Now safe to delete tool_calls (no messages reference them)
      ToolCall.where(message_id: message_ids).delete_all

      # Delete message dependents
      Mention.where(message_id: message_ids).delete_all
      ActiveStorage::Attachment.where(record_type: "Message", record_id: message_ids).delete_all

      # Delete messages and chat runs
      @chat.messages.delete_all
      @chat.chat_runs.delete_all
    end

    head :no_content
  end

  def leave
    authorize @chat, :leave?
    
    chat_member = @chat.chat_members.find_by(member: current_member)
    
    if chat_member
      @chat.messages.create!(
        role: 'assistant',
        content: "#{current_member.user.name} left the chat",
        user_submitted: false,
        metadata: { system_event: 'member_left', member_name: current_member.user.name }
      )
      
      chat_member.destroy
      
      respond_to do |format|
        format.html { redirect_to chats_path, notice: "Left chat successfully" }
        format.json { head :no_content }
      end
    else
      respond_to do |format|
        format.html { redirect_to chat_path(@chat), alert: "Could not leave chat" }
        format.json { render json: { error: 'Could not leave chat' }, status: :unprocessable_content }
      end
    end
  end
  
  private
  
  def set_chat
    chat_id = params[:id]
    
    @chat = if chat_id.to_s.start_with?('chat_')
      current_member.chats.find_by_prefix_id(chat_id)
    else
      current_member.chats.find_by(id: chat_id)
    end
    
    unless @chat
      redirect_to chats_path, alert: 'Chat not found'
    end
  end
  
  def chat_params
    params.require(:chat).permit(:name)
  end

end
