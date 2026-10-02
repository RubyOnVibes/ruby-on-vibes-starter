# frozen_string_literal: true

class ChatRunsController < ApplicationController
  before_action :authenticate_user!
  before_action :set_chat_run

  # POST /chat_runs/:id/cancel
  def cancel
    authorize @chat_run.chat, :cancel_runs?

    if @chat_run.cancel!(cancelled_by: current_user.email)
      render json: { status: 'cancelled' }, status: :ok
    else
      render json: { error: 'Failed to cancel chat run' }, status: :unprocessable_content
    end
  end

  # POST /chat_runs/:id/continue
  # Triggered by frontend when all agent tasks have completed during awaiting_tasks state.
  # Resumes the chat run so the assistant can summarize task results.
  def continue
    authorize @chat_run.chat, :send_messages?

    unless @chat_run.status_awaiting_tasks?
      render json: { error: 'Chat run is not awaiting tasks' }, status: :conflict
      return
    end

    # Count assistant messages created during this run to track continuation depth.
    # Prevents infinite loops if the LLM keeps creating tasks during continuations.
    depth = @chat_run.chat.messages.where(role: :assistant)
      .where("created_at >= ?", @chat_run.created_at).count

    @chat_run.update!(status: :running)

    # Trigger a continuation ChatStreamJob
    # Pass nil for user_msg_id — continuation mode has no triggering user message
    # Pass sender context so the job knows who to attribute the response to
    ChatStreamJob.perform_later(
      @chat_run.chat_id, nil, @chat_run.id,
      sender_member_id: (@chat_run.initiated_by_member_id || current_member.id),
      sender_user_id: (@chat_run.initiated_by_member&.user_id || current_user.id),
      task_continuation: true,
      continuation_depth: depth
    )

    render json: { status: 'continuing' }, status: :ok
  end

  def approve_tool
    decide_tool("approved")
  end

  def deny_tool
    decide_tool("denied")
  end

  private

  def set_chat_run
    @chat_run = ChatRun.find(params[:id])
  end

  def decide_tool(decision)
    authorize @chat_run.chat, :approve_tools?

    tool_call, should_resume = @chat_run.decide_tool_call!(
      params[:tool_call_id],
      decision: decision,
      member: current_member
    )

    tool_call.message.broadcast_upsert_to_chat! if tool_call.message.respond_to?(:broadcast_upsert_to_chat!)

    if should_resume
      initiator = @chat_run.initiated_by_member || current_member
      ChatStreamJob.perform_later(
        @chat_run.chat_id,
        nil,
        @chat_run.id,
        sender_member_id: initiator.id,
        sender_user_id: initiator.user_id,
        approval_resume: true
      )
    end

    render json: {
      status: decision,
      resuming: should_resume,
      pending_approvals: @chat_run.pending_tool_approvals.size
    }, status: :ok
  rescue ChatRun::ToolCallAlreadyDecided
    render json: { error: "Tool call has already been decided" }, status: :conflict
  end
end
