# frozen_string_literal: true

##
# CancelAgentTaskTool - Cancel a running agent task
#
# The background job periodically checks task.status_cancelled?
# and stops execution within a few seconds of cancellation.
#
class CancelAgentTaskTool < RubyLLM::Tool
  description "Cancel a running or pending agent task in this chat."

  params do
    string :task_id, description: "The agent task ID to cancel (e.g. agent_task_xxx)", required: true
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
    return { error: "Task is already #{task.status}." } unless task.active?

    task.cancel!
    { success: true, message: "Task #{task.to_param} has been cancelled." }
  end
end
