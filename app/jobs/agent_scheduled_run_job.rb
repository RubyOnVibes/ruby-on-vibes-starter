# frozen_string_literal: true

##
# AgentScheduledRunJob - Triggers a scheduled agent run.
#
# Called by SolidQueue recurring schedule. Creates a trigger message
# in the agent's chat, creates an AgentTask for tracking, and enqueues
# a ChatStreamJob to generate the agent's response.
#
# The agent's creator member is the actor for scheduled runs.
# The trigger column on AgentTask distinguishes this from human-initiated work.
#
class AgentScheduledRunJob < SolidQueueJob
  def perform(agent_id)
    agent = Agent.find_by(id: agent_id)
    return unless agent&.active?

    chat = agent.chat
    member = agent.member

    # Auto-compact before run to keep agent within context limits (best-effort).
    # Future: gate this on a token-count check so we only compact when actually
    # near the model's window — currently compact_if_needed! decides internally.
    begin
      Chat::CompactionService.new(chat).compact_if_needed!
    rescue => e
      Rails.logger.error "[AgentScheduledRunJob] Compaction failed, continuing: #{e.class} - #{e.message}"
    end

    # Create a trigger message in the agent's chat
    chat.messages.create!(
      role: :user,
      content: "Scheduled run: #{Time.current.strftime('%b %d, %Y %l:%M%P').strip}",
      user_submitted: false
    )

    # Create an AgentTask for tracking
    task = AgentTask.create!(
      chat: chat,
      workspace: agent.workspace,
      member: member,
      kind: "scheduled_run",
      trigger: "schedule"
    )

    # Create a ChatRun and trigger the chat stream (same path as user messages)
    chat_run = chat.chat_runs.create!(status: :pending)

    ChatStreamJob.perform_later(
      chat.id,
      nil,  # no user message (continuation-style)
      chat_run.id,
      { sender_member_id: member.id, sender_user_id: member.user_id }
    )

    Rails.logger.info "[AgentScheduledRunJob] Triggered scheduled run for agent '#{agent.identifier}' (task: #{task.to_param})"
  end
end
