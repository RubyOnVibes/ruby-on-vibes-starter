# frozen_string_literal: true

# Application intent, actor and usage for one native conversation execution.
# Native RubyLLM messages, claims, questions and tasks remain authoritative.
class ChatRun < ApplicationRecord
  belongs_to :chat
  belongs_to :input_message, class_name: "Message", inverse_of: :triggered_chat_runs, optional: true
  validate :input_message_belongs_to_chat
  belongs_to :initiated_by_member, class_name: "Member", optional: true
  has_one :agent_delivery, dependent: :nullify, inverse_of: :chat_run
  has_many :example_report_publications, class_name: "Examples::ReportPublication", inverse_of: :chat_run, dependent: :nullify
  has_many :owned_llm_usages, class_name: "RubyLLM::ActiveRecord::Usage", as: :owner, dependent: :nullify

  enum :status, {
    pending: 0,
    running: 1,
    completed: 2,
    cancelled: 3,
    failed: 4,
    awaiting_tasks: 5,
    awaiting_approval: 6
  }, prefix: true

  scope :active, -> { where(status: [ :pending, :running, :awaiting_tasks, :awaiting_approval ]) }
  scope :for_chat, ->(chat) { where(chat: chat) }

  # Capture node name on creation
  before_create :set_node_name

  # Auto-set completion timestamps when status changes
  before_update :set_completion_timestamps, if: :status_changed?

  # Broadcast state changes to chat stream
  after_commit :broadcast_state_change, on: [ :create, :update ]

  def active?
    status_pending? || status_running? || status_awaiting_tasks? || status_awaiting_approval?
  end

  # The persisted intent is the outbox. If enqueueing or a worker dies, the
  # recurring recovery job can redeliver it without reconstructing a browser request.
  def dispatch!(wait: 0)
    with_lock do
      return false unless active?
      update!(resume_at: Time.current + wait)
    end
    begin
      job = if wait.positive?
        ChatStreamJob.set(wait_until: resume_at).perform_later(id)
      else
        ChatStreamJob.perform_later(id)
      end
      job != false
    rescue StandardError => error
      Rails.logger.error("[ChatRun] Enqueue failed for #{id}: #{error.class}")
      false
    end
  end

  def execution_member!
    actor = initiated_by_member
    raise Pundit::NotAuthorizedError, "The initiating member no longer has access" unless actor && chat.member_exists?(actor)
    actor
  end

  # Only native tasks may park the tool loop. An input-required task needs an
  # authorized application callback; polling must never silently answer it.
  def resume_tasks!(explicit: false)
    with_lock do
      return false unless status_awaiting_tasks?
      return false if chat.running?
      tasks = chat.pending_tasks
      return false if !explicit && tasks.any? && tasks.all?(&:input_required?)
      # This only delivers intent; the worker reauthorizes before any provider
      # or tool work, including when the original actor has since lost access.
      update!(status: :running, resume_at: Time.current)
    end
    dispatch!
  end

  def recover!
    return false unless active?
    return false if chat.running?
    return false if resume_at&.future?
    return resume_tasks! if status_awaiting_tasks?
    return false if status_awaiting_approval?
    dispatch!
  end

  def transition_to_awaiting_tasks!
    update!(status: :awaiting_tasks)
  end

  def transition_to_awaiting_approval!
    update!(status: :awaiting_approval)
  end

  # Persist an approval decision and atomically claim the resume. The tool call
  # metadata is written when ChatStreamJob parks the run, so decisions remain
  # safe across process restarts and cannot target another chat's tool call.
  def decide_tool_call!(tool_call_id, decision:, member:)
    raise ArgumentError, "invalid decision" unless %w[approved denied].include?(decision.to_s)

    answer_question!(tool_call_id, member: member, decision: decision, approval_only: true)
  end

  def answer_question!(question_id, member:, decision: "answered", answer: nil, note: nil, approval_only: false)
    raise ArgumentError, "invalid decision" unless %w[answered approved denied declined].include?(decision.to_s)

    should_resume = false
    tool_call = nil

    with_lock do
      raise ActiveRecord::RecordNotFound unless status_awaiting_approval?

      question = pending_questions.find { |candidate| candidate.id == question_id.to_s }
      raise ActiveRecord::RecordNotFound unless question
      raise ActiveRecord::RecordNotFound if approval_only && !question.approval?
      tool_call = approval_tool_calls.find { |candidate| candidate.tool_call_id == question.tool_call.id }

      execution_member!
      unless can_decide?(member: member, tool_call: tool_call)
        raise Pundit::NotAuthorizedError, "not allowed to decide this tool call"
      end

      case decision.to_s
      when "approved" then question.approve
      when "denied", "declined" then question.decline(note)
      else question.answer(answer)
      end

      tool_call.reload.update!(
        metadata: tool_call.metadata.merge(
          "decided_by_member_id" => member.id,
          "decided_at" => Time.current.iso8601
        )
      )

      if pending_questions.empty?
        update!(status: :running, resume_at: Time.current)
        should_resume = true
      end
    end

    [ tool_call, should_resume ]
  end

  def approval_tool_calls
    message_ids = chat.messages.where("created_at >= ?", created_at).select(:id)

    RubyLLM::ActiveRecord::ToolCall
      .where(message_type: Message.polymorphic_name, message_id: message_ids)
      .order(:id)
      .to_a
      .select { |tool_call| tool_call.metadata["chat_run_id"].to_i == id }
  end

  def pending_tool_approvals
    approval_tool_calls.select do |tool_call|
      tool_call.metadata["requires_approval"] && tool_call.approval.in?([ nil, "pending" ])
    end
  end

  # Use RubyLLM's persisted questions, scoped to this run.
  def pending_questions
    calls = approval_tool_calls
    call_ids = calls.map(&:tool_call_id)
    questions = chat.pending_questions.select { |question| call_ids.include?(question.tool_call.id) }
    # HTTP reads have no agent toolset bound. Reconstruct the native question
    # from the approval metadata written when the authorized worker parked.
    pending_tool_approvals.each do |call|
      next if call.result_id.present? || questions.any? { |question| question.id == call.tool_call_id }
      questions << RubyLLM::Question.approval(call.to_llm, chat: chat)
    end
    questions
  end

  # Customize this application policy for tools requiring a separate reviewer.
  # A confirmation defaults to the recorded requester or the chat owner.
  def can_decide?(member:, tool_call:)
    member && chat.member_exists?(member) &&
      (tool_call.metadata["requester_member_id"].to_i == member.id || chat.owner?(member))
  end

  def capture_usage!
    usages = owned_llm_usages.chronological.to_a
    return usage_summary if usages.empty?

    tokens = RubyLLM::Tokens.aggregate(usages.map(&:tokens))
    cost = RubyLLM::Cost.aggregate(usages.map(&:cost), complete: usages.all?(&:cost_available?))

    update_columns(
      llm_attempts: usages.size,
      input_tokens: tokens.input,
      output_tokens: tokens.output,
      cache_read_tokens: tokens.cache_read,
      cache_write_tokens: tokens.cache_write,
      thinking_tokens: tokens.thinking,
      total_cost: cost.total,
      usage_metadata: {
        "providers" => usages.map(&:provider).uniq,
        "models" => usages.map(&:model).uniq,
        "operations" => usages.map(&:operation).uniq,
        "server_tool_use" => tokens.server_tool_use,
        "statuses" => usages.group_by(&:status).transform_values(&:size)
      },
      updated_at: Time.current
    )

    usage_summary
  end

  def usage_summary
    {
      "attempts" => llm_attempts,
      "input_tokens" => input_tokens,
      "output_tokens" => output_tokens,
      "cache_read_tokens" => cache_read_tokens,
      "cache_write_tokens" => cache_write_tokens,
      "thinking_tokens" => thinking_tokens,
      "total_cost" => total_cost&.to_s,
      "providers" => usage_metadata.fetch("providers", []),
      "models" => usage_metadata.fetch("models", [])
    }.compact
  end

  def stopping?
    status_cancelled? || status_failed?
  end

  def ended_at
    completed_at || cancelled_at || failed_at || updated_at
  end

  def messages_during_run
    return [] unless ended_at

    chat.messages.where(created_at: created_at..ended_at)
  end

  def cancel!(cancelled_by: nil)
    return true if status_completed? || status_cancelled?

    with_lock do
      return true unless active?
      chat.cancel
      begin
        # Settle parked calls before another submitted message can obscure
        # their response. This only processes cancellation, never a provider
        # request; if a worker owns the native claim, it observes the flag.
        chat.run_tools
      rescue RubyLLM::CancelledError
        # Native cancellation has persisted the unfinished tool results.
      end
      update!(status: :cancelled, cancelled_by: cancelled_by, resume_at: nil)
    end

    true
  end

  private

  def input_message_belongs_to_chat
    errors.add(:input_message, "must belong to this chat") if input_message && input_message.chat_id != chat_id
  end

  def set_node_name
    self.node_name = current_node_name
  end

  def current_node_name
    ENV["NODE_NAME"] || Socket.gethostname
  end

  def set_completion_timestamps
    case status
    when "completed"
      self.completed_at = Time.current
    when "cancelled"
      self.cancelled_at = Time.current
    when "failed"
      self.failed_at = Time.current
    end
  end

  def broadcast_state_change
    stream_name = "chat_#{chat_id}"

    Turbo::StreamsChannel.broadcast_replace_to(
      stream_name,
      target: "chat-run-state",
      partial: "chat_runs/state",
      locals: { chat_run: self }
    )
  rescue => e
    Rails.logger.error "[ChatRun] ❌ Broadcast failed: #{e.class} - #{e.message}"
    Rails.logger.error e.backtrace.first(5).join("\n")
  end
end
