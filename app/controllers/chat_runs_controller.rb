# frozen_string_literal: true

class ChatRunsController < ApplicationController
  before_action :authenticate_user!
  before_action :set_chat_run

  # POST /chat_runs/:id/cancel
  def cancel
    authorize @chat_run.chat, :cancel_runs?

    if @chat_run.cancel!(cancelled_by: current_user.email)
      render json: { status: "cancelled" }, status: :ok
    else
      render json: { error: "Failed to cancel chat run" }, status: :unprocessable_content
    end
  end

  # POST /chat_runs/:id/continue
  # Explicit user signal for a native input-required task. The tool must still
  # verify its external/domain completion state in resume.
  def continue
    authorize @chat_run.chat, :send_messages?

    unless @chat_run.status_awaiting_tasks?
      render json: { error: "Chat run is not awaiting tasks" }, status: :conflict
      return
    end

    unless @chat_run.resume_tasks!(explicit: true)
      render json: { error: "Tasks are still running" }, status: :conflict
      return
    end

    render json: { status: "continuing" }, status: :ok
  end

  def approve_tool
    decide_tool("approved")
  end

  def deny_tool
    decide_tool("denied")
  end

  def answer_question
    decide_question("answered", answer: params[:answer])
  end

  def decline_question
    decide_question("declined", note: params[:note])
  end

  private

  def set_chat_run
    @chat_run = ChatRun.find(params[:id])
  end

  def decide_tool(decision)
    decide_question(decision, question_id: params[:tool_call_id], approval_only: true)
  end

  def decide_question(decision, question_id: params[:question_id], **options)
    authorize @chat_run.chat, :approve_tools?

    tool_call, should_resume = @chat_run.answer_question!(
      question_id,
      decision: decision,
      member: current_member,
      **options
    )

    tool_call.message.broadcast_upsert_to_chat! if tool_call.message.respond_to?(:broadcast_upsert_to_chat!)

    @chat_run.dispatch! if should_resume

    render json: {
      status: decision,
      resuming: should_resume,
      pending_approvals: @chat_run.pending_tool_approvals.size,
      pending_questions: @chat_run.pending_questions.size
    }, status: :ok
  rescue RubyLLM::ToolCallRunningError
    render json: { error: "Tool call has already been decided" }, status: :conflict
  rescue ArgumentError => e
    render json: { error: e.message }, status: :unprocessable_content
  end
end
