# frozen_string_literal: true

##
# AgentProvisioner - Idempotently creates agents from blueprint config.
#
# Called when loading the chats page to ensure workspace agents exist.
# Keyed on identifier — agents that already exist are skipped.
#
# Blueprint config lives in config/agent_blueprints.yml, organized by
# workspace type (default applies to all workspaces).
#
#   AgentProvisioner.provision!(workspace)
#
class AgentProvisioner
  class << self
    def provision!(workspace)
      return unless RubyOnVibes.agents?

      blueprints = blueprints_for(workspace)
      return if blueprints.blank?

      owner_member = workspace.members.find_by(user_id: workspace.owner_id)
      return unless owner_member

      existing_identifiers = workspace.agents.pluck(:identifier)

      blueprints.each do |identifier, config|
        next if existing_identifiers.include?(identifier.to_s)

        Agent.create_from_blueprint!(
          workspace: workspace,
          member: owner_member,
          identifier: identifier.to_s,
          **config.symbolize_keys
        )

        Rails.logger.info "[AgentProvisioner] Created agent '#{identifier}' for workspace #{workspace.id}"
      end
    end

    private

    def blueprints_for(workspace)
      config = load_config
      return {} if config.blank?

      # Future: workspace.metadata["agent_blueprint_type"] || "default"
      workspace_type = "default"
      config[workspace_type] || {}
    end

    def load_config
      @config = nil if Rails.env.development? # Reload in dev
      @config ||= begin
        path = Rails.root.join("config", "agent_blueprints.yml")
        return {} unless File.exist?(path)

        YAML.load_file(path) || {}
      end
    end
  end
end
