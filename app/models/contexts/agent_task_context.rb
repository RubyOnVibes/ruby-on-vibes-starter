# frozen_string_literal: true

##
# AgentTaskContext - Structured LLM context for AgentTask records
#
# Provides schema-driven serialization for agent tasks when mentioned
# or when injecting completed task results into chat instructions.
#
class AgentTaskContext < RecordContext
  schema do
    description "A background task executed by an AI agent"

    string :id, description: "Prefixed task ID (agent_task_xxx)"
    string :kind, description: "Task type identifier (e.g., customer_analysis, data_export)"
    string :status, description: "Current status: pending, running, completed, failed, cancelled, awaiting_approval"
    integer :progress, description: "Completion percentage (0-100)", minimum: 0, maximum: 100
    string :progress_text, required: false, description: "Human-readable progress message"
    integer :attempts, description: "Number of execution attempts"

    string :chat_id, description: "Chat that spawned this task"
    string :member_id, description: "Member who triggered this task"
    string :path, description: "CLICKABLE PATH - use this for markdown links to this task"

    string :result_json, required: false, description: "Structured output as JSON (when completed or awaiting approval)"
    string :error_message, required: false, description: "Error details (when failed)"
    string :effects_summary, required: false, description: "Summary of actions taken: records created/updated/deleted, files attached/detached"

    string :started_at, required: false, description: "When execution began (ISO8601)"
    string :completed_at, required: false, description: "When execution finished (ISO8601)"
    string :created_at, description: "When the task was created (ISO8601)"
  end

  ##
  # Create context from AgentTask record
  #
  # @param task [AgentTask] The task to serialize
  # @return [AgentTaskContext] Context instance
  #
  def self.from_record(task)
    data = {
      id: task.to_param,
      kind: task.kind,
      status: task.status,
      progress: task.progress,
      attempts: task.attempts,
      chat_id: task.chat.to_param,
      member_id: task.member.to_param,
      path: Rails.application.routes.url_helpers.agent_task_path(task),
      created_at: task.created_at.iso8601
    }

    data[:progress_text] = task.progress_text if task.progress_text.present?
    data[:started_at] = task.started_at.iso8601 if task.started_at
    data[:completed_at] = task.completed_at.iso8601 if task.completed_at

    if task.status_completed? || task.status_awaiting_approval?
      data[:result_json] = task.result.to_json
    end

    data[:error_message] = task.error_message if task.status_failed? && task.error_message.present?

    if task.effects.loaded? ? task.effects.any? : task.effects.exists?
      summaries = task.effects.by_recency.map do |effect|
        line = "#{effect.action}: #{effect.description}"
        line += " (#{effect.target_type} ##{effect.target_id})" if effect.target_type.present?
        line
      end
      data[:effects_summary] = summaries.join("; ")
    end

    new(data)
  end

  def summary
    parts = [data[:kind].humanize, data[:status]]
    parts << data[:progress_text] if data[:progress_text].present?
    if data[:effects_summary].present?
      parts << data[:effects_summary].truncate(100)
    end
    parts.join(" — ")
  end
end
