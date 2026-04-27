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
#                     → awaiting_tasks → running (continuation) → (completed | cancelled | failed)
#
# ARCHITECTURE NOTE:
# - ChatRun tracks JOB EXECUTION (when, status, which node)
# - Message tracks CONTENT (what the LLM said)
# - Related via time window + chat_id, not direct FK
# - This separation allows one run to involve multiple messages (tool use, retries)
#
class ChatRun < ApplicationRecord
  belongs_to :chat

  enum :status, {
    pending: 0,
    running: 1,
    completed: 2,
    cancelled: 3,
    failed: 4,
    awaiting_tasks: 5
  }, prefix: true

  scope :active, -> { where(status: [:pending, :running, :awaiting_tasks]) }
  scope :for_chat, ->(chat) { where(chat: chat) }
  
  # Capture node name on creation
  before_create :set_node_name
  
  # Auto-set completion timestamps when status changes
  before_update :set_completion_timestamps, if: :status_changed?
  
  # Broadcast state changes to chat stream
  after_commit :broadcast_state_change, on: [:create, :update]

  def active?
    status_pending? || status_running? || status_awaiting_tasks?
  end

  def transition_to_awaiting_tasks!
    update!(status: :awaiting_tasks)
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
        orphaned_tool_calls = ToolCall.where(message_id: processing_message.id)
        if orphaned_tool_calls.any?
          tool_call_record_ids = orphaned_tool_calls.pluck(:id)
          Rails.logger.info "[ChatRun] Deleting #{orphaned_tool_calls.count} orphaned tool calls"

          # Delete tool messages BEFORE destroying ToolCall records (prevents FK issues)
          chat.messages.where(role: 'tool', tool_call_id: tool_call_record_ids).destroy_all
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

