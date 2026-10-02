# frozen_string_literal: true

##
# ChatRun - Tracks a single chat job execution
#
# Enables graceful cancellation of streaming responses.
# Each chat can have only ONE active run at a time.
#
# MULTI-NODE SAFE:
# - Tracks node_name to identify which server is running the job
# - Relies on polling (ChatStreamJob checks stopping?) for cancellation
#
# Status flow:
#   pending → running → (completed | cancelled | failed)
#                     → awaiting_tasks → running (continuation)
#                     → awaiting_approval → running (approved/denied)
#
# ARCHITECTURE NOTE:
# - ChatRun tracks JOB EXECUTION (when, status, which node)
# - Message tracks CONTENT (what the LLM said)
# - Related via time window + chat_id, not direct FK
# - This separation allows one run to involve multiple messages (tool use, retries)
#
class ChatRun < ApplicationRecord
  class ToolCallAlreadyDecided < StandardError; end

  belongs_to :chat
  belongs_to :initiated_by_member, class_name: "Member", optional: true

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
  after_commit :broadcast_state_change, on: [:create, :update]

  def active?
    status_pending? || status_running? || status_awaiting_tasks? || status_awaiting_approval?
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

    should_resume = false
    tool_call = nil

    with_lock do
      raise ActiveRecord::RecordNotFound unless status_awaiting_approval?

      tool_call = approval_tool_calls.find { |candidate| candidate.tool_call_id == tool_call_id.to_s }
      raise ActiveRecord::RecordNotFound unless tool_call
      raise ActiveRecord::RecordNotFound unless tool_call.metadata["requires_approval"]
      raise ToolCallAlreadyDecided if tool_call.approval.present?

      requester_id = tool_call.metadata["requester_member_id"]&.to_i
      unless member && (requester_id == member.id || chat.owner?(member))
        raise Pundit::NotAuthorizedError, "not allowed to decide this tool call"
      end

      tool_call.update!(
        approval: decision,
        metadata: tool_call.metadata.merge(
          "decided_by_member_id" => member.id,
          "decided_at" => Time.current.iso8601
        )
      )

      if pending_tool_approvals.empty?
        update!(status: :running)
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
      tool_call.metadata["requires_approval"] && tool_call.approval.blank?
    end
  end

  # Snapshot provider attempts attributable to this run. A chat can have only
  # one active run, so the run's time window is an unambiguous accounting scope,
  # including retries and approval/task continuations.
  def capture_usage!
    usages = chat.ruby_llm_usages.where("created_at >= ?", created_at).chronological.to_a
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

    transaction do
      update!(status: :cancelled, cancelled_by: cancelled_by)

      # Cancel all active agent tasks for this chat.
      # Whether we're mid-stream (running) or waiting (awaiting_tasks),
      # stopping means "stop everything."
      chat.agent_tasks.active.find_each(&:cancel!)

      # Find the most recent assistant message created during this run
      # This should be the message currently being streamed
      #
      processing_message = chat.messages
        .where(role: :assistant)
        .where('created_at >= ?', created_at)
        .order(created_at: :desc)
        .first
      
      if processing_message
        processing_message.update!(
          content: "",  # Empty content - UI shows "Cancelled"
          skip_llm_context: true,  # Never include cancelled messages in LLM context
          metadata: (processing_message.metadata || {}).merge(cancelled: true)
        )
        
        # Clean up orphaned tool calls to prevent RubyLLM validation errors
        # When we cancel mid-tool-execution, RubyLLM expects tool result messages
        # but we skip them, so we must clean up the tool_calls entirely
        orphaned_tool_calls = processing_message.ruby_llm_tool_calls
        if orphaned_tool_calls.any?
          Rails.logger.info "[ChatRun] Deleting #{orphaned_tool_calls.count} orphaned tool calls"

          # Delete tool result messages before their tool-call records.
          orphaned_tool_calls.includes(:result).filter_map(&:result).each(&:destroy!)
          orphaned_tool_calls.destroy_all
        end
        
        processing_message.broadcast_full_replace!
      end
    end

    true
  end

  private
  
  def set_node_name
    self.node_name = current_node_name
  end
  
  def current_node_name
    ENV['NODE_NAME'] || Socket.gethostname
  end
  
  def set_completion_timestamps    
    case status
    when 'completed'
      self.completed_at = Time.current
    when 'cancelled'
      self.cancelled_at = Time.current
    when 'failed'
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
