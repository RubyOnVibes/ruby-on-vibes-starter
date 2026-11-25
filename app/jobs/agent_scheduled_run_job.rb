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

    chat.with_lock do
      return if chat.chat_runs.active.exists? || chat.running?
      trigger_message = chat.messages.create!(role: :user,
        content: "Scheduled run: #{Time.current.iso8601}", user_submitted: false)
      @run = chat.chat_runs.create!(status: :pending, initiated_by_member: member,
        input_message: trigger_message, trigger: "schedule")
    end
    @run.dispatch!
  end
end
