# frozen_string_literal: true

##
# ListAgentTasksTool - List agent tasks in the current chat
#
# Gives the LLM full visibility into the task history of the chat.
# Supports filtering by status and kind.
#
class ListAgentTasksTool < RubyLLM::Tool
  description "List agent tasks in this chat. Returns task IDs, kinds, statuses, and summaries. " \
              "Use this to check what tasks have been run, are running, or have completed."

  params do
    string :status, description: "Filter by status: pending, running, completed, failed, cancelled, awaiting_approval, or 'all' (default: all)", required: false
    string :kind, description: "Filter by task kind (e.g. 'customer_analysis')", required: false
    integer :limit, description: "Maximum number of tasks to return (default: 20)", required: false
  end

  attr_reader :chat, :sender_user, :sender_member, :sender_workspace

  def initialize(chat:, sender_user: nil, sender_member: nil, sender_workspace: nil)
    @chat = chat
    @sender_user = sender_user
    @sender_member = sender_member
    @sender_workspace = sender_workspace
  end

  def execute(status: nil, kind: nil, limit: nil)
    limit = [[limit.to_i, 1].max, 50].min if limit.present?
    limit ||= 20

    scope = @chat.agent_tasks.order(created_at: :desc)

    if status.present? && status != "all"
      valid_statuses = AgentTask.statuses.keys
      return { error: "Invalid status '#{status}'. Valid: #{valid_statuses.join(', ')}" } unless valid_statuses.include?(status)
      scope = scope.where(status: AgentTask.statuses[status])
    end

    scope = scope.where(kind: kind) if kind.present?

    tasks = scope.limit(limit).map do |task|
      {
        id: task.to_param,
        kind: task.kind,
        status: task.status,
        progress: task.progress,
        summary: task.mentionable_summary,
        created_at: task.created_at.iso8601,
        completed_at: task.completed_at&.iso8601
      }
    end

    {
      tasks: tasks,
      total_count: @chat.agent_tasks.count,
      showing: tasks.size
    }
  end
end
