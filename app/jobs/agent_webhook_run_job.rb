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

    task.start!
    chat = agent.chat
    member = agent.member

    # Auto-compact before run to keep agent within context limits (best-effort)
    begin
      Chat::CompactionService.new(chat).compact_if_needed!
    rescue => e
      Rails.logger.error "[AgentWebhookRunJob] Compaction failed, continuing: #{e.class} - #{e.message}"
    end

    # Create a ChatRun and trigger the chat stream
    chat_run = chat.chat_runs.create!(status: :pending)

    ChatStreamJob.perform_later(
      chat.id,
      nil,  # no user message (continuation-style)
      chat_run.id,
      { sender_member_id: member.id, sender_user_id: member.user_id }
    )

    Rails.logger.info "[AgentWebhookRunJob] Triggered webhook run for agent '#{agent.identifier}' (task: #{task.to_param})"
  end
end
