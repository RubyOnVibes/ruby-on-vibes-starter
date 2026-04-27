# frozen_string_literal: true

##
# AgentContext - Structured LLM context for Agent records
#
# Provides schema-driven serialization for persistent agents when
# @mentioned in chat.
#
class AgentContext < RecordContext
  schema do
    description "A persistent autonomous agent with identity, instructions, and optional schedule"

    string :id, description: "Prefixed agent ID (agent_xxx)"
    string :name, description: "Display name"
    string :identifier, description: "Unique identifier within workspace (lowercase_with_underscores)"
    string :status, description: "Active or inactive"
    string :schedule, required: false, description: "Cron expression for scheduled runs"
    string :instructions_preview, description: "First 200 chars of the agent's instructions"
    string :chat_id, description: "The agent's persistent chat ID"
    string :path, description: "CLICKABLE PATH - use this for markdown links to this agent"
    string :created_at, description: "When the agent was created (ISO8601)"
  end

  def self.from_record(agent)
    instructions = agent.resolved_instructions

    data = {
      id: agent.to_param,
      name: agent.name,
      identifier: agent.identifier,
      status: agent.active? ? "active" : "inactive",
      instructions_preview: instructions.truncate(200),
      chat_id: agent.chat.to_param,
      path: Rails.application.routes.url_helpers.agent_path(agent),
      created_at: agent.created_at.iso8601
    }

    data[:schedule] = agent.schedule if agent.schedule.present?

    new(data)
  end

  def summary
    parts = [data[:name]]
    parts << data[:status]
    parts << "schedule: #{data[:schedule]}" if data[:schedule]
    parts.join(" — ")
  end
end
