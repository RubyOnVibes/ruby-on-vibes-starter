# frozen_string_literal: true

##
# AgentWebhookRunJob - Processes a webhook-triggered agent run.
#
# The webhook payload is already posted as a message in the agent's chat
# and stored as metadata on the AgentTask. This job creates a ChatRun
# and triggers a ChatStreamJob so the agent can reason about the webhook.
#
class AgentWebhookRunJob < SolidQueueJob
  def perform(agent_id, agent_task_id)
    agent = Agent.find_by(id: agent_id)
    task = AgentTask.find_by(id: agent_task_id)
    return unless agent&.active?
    return if task.nil? || task.terminal?
    return unless task.chat_id == agent.chat_id

    chat = agent.chat
    chat.with_lock do
      return if chat.chat_runs.active.exists? || chat.running?
      return if task.reload.terminal?
      trigger_id = task.metadata["trigger_message_id"]
      message = trigger_id ? chat.messages.find(trigger_id) : chat.messages.where(role: :user, user_submitted: false).order(:id).last
      @run = chat.chat_runs.create!(status: :pending, initiated_by_member: agent.member,
        input_message: message, trigger: "webhook")
      # This record tracks webhook receipt/delivery, not the conversation's work.
      task.complete!({ "chat_run_id" => @run.id })
    end
    @run.dispatch!
  end
end
