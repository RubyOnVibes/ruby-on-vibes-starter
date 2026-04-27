# frozen_string_literal: true

##
# AgentTaskStatusTool - Check the status and result of an agent task
#
# Lets the LLM inspect any task in the current chat.
# Returns status, progress, result (if completed), and effects summary.
#
# TODO: Add an "undo" capability that reverses tracked effects:
#   - created → destroy the record
#   - updated → revert to "from" values in changes
#   - deleted → recreate from snapshot
#   - attached → detach
#   - detached → re-attach (requires file content to be recoverable)
#   This could be a separate UndoAgentTaskTool or a parameter on this tool.
#
class AgentTaskStatusTool < RubyLLM::Tool
  description "Check the status, progress, result, and side effects of an agent task in this chat. " \
              "Use this to inspect what a task did (records created, updated, deleted, files attached, etc.)."

  params do
    string :task_id, description: "The agent task ID (e.g. agent_task_xxx)", required: true
  end

  attr_reader :chat, :sender_user, :sender_member, :sender_workspace

  def initialize(chat:, sender_user: nil, sender_member: nil, sender_workspace: nil)
    @chat = chat
    @sender_user = sender_user
    @sender_member = sender_member
    @sender_workspace = sender_workspace
  end

  def execute(task_id:)
    task = @chat.agent_tasks.find_by_prefix_id(task_id)
    return { error: "Task '#{task_id}' not found in this chat." } unless task

    response = {
      id: task.to_param,
      kind: task.kind,
      status: task.status,
      progress: task.progress,
      progress_text: task.progress_text,
      started_at: task.started_at&.iso8601,
      completed_at: task.completed_at&.iso8601
    }

    response[:result] = task.result if task.status_completed? || task.status_awaiting_approval?
    response[:error_message] = task.error_message if task.status_failed?

    # Include effects summary so the LLM can report what the task actually did
    effects = task.effects.by_recency
    if effects.any?
      response[:effects_summary] = {
        total: effects.size,
        by_action: effects.group(:action).count,
        details: effects.map { |e|
          entry = { action: e.action, description: e.description }
          entry[:target] = "#{e.target_type} ##{e.target_id}" if e.target_type.present?
          entry
        }
      }
    end

    # Include subtask info if any exist
    subtask_count = task.subtasks.count
    if subtask_count > 0
      response[:subtasks] = task.subtasks.map { |s|
        { id: s.to_param, kind: s.kind, status: s.status }
      }
    end

    response
  end
end
