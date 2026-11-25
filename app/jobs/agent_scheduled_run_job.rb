# frozen_string_literal: true

# Scheduled events use the same durable inbox and execution path as webhooks.
# A scheduler can supply a stable occurrence key (slot). Without one, repeated
# delivery of this serialized Active Job is deduplicated by its job_id.
class AgentScheduledRunJob < ApplicationJob
  queue_as :agents

  def perform(agent_id, slot: nil)
    agent = Agent.find_by(id: agent_id)
    return unless agent&.active?

    key = slot.present? ? "slot:#{slot}" : "job:#{job_id}"
    AgentDelivery.accept!(agent: agent, trigger: "schedule", idempotency_key: key).dispatch!
  end
end
