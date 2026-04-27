# frozen_string_literal: true

##
# Agent - A persistent, autonomous worker with identity, instructions, and optional schedule.
#
# An Agent is a thin config wrapper around a Chat. The chat is the agent's
# work log and the human's interface to steer it. The Agent adds:
#
#   - Identity: name, identifier (unique per workspace)
#   - Instructions: custom system prompt (inline text or prompt file reference)
#   - Tool config: which tools the agent has access to (nil = defaults)
#   - Schedule: cron expression for autonomous runs (nil = manual/webhook only)
#   - Webhook token: secret URL for receiving external events
#
# Agents are created from blueprints (config/agent_blueprints.yml) on workspace
# provisioning, or manually by users through the UI.
#
# The agent's creator member is the "actor" for automated runs (scheduled, webhook).
# The `trigger` column on AgentTask distinguishes human-initiated from automated work.
#
class Agent < ApplicationRecord
  has_prefix_id :agent

  include Mentionable

  belongs_to :workspace
  belongs_to :member        # creator/owner — automated runs act on their behalf
  belongs_to :chat

  has_many :agent_tasks, through: :chat

  validates :name, presence: true
  validates :identifier, presence: true,
    uniqueness: { scope: :workspace_id },
    format: { with: /\A[a-z][a-z0-9_]*\z/, message: "must be lowercase with underscores" }

  before_create :generate_webhook_token

  scope :active, -> { where(active: true) }
  scope :scheduled, -> { active.where.not(schedule: [nil, ""]) }
  scope :webhook_enabled, -> { active.where.not(webhook_token: nil) }

  def scheduled?
    schedule.present?
  end

  def webhook_url
    return nil unless webhook_token.present?

    Rails.application.routes.url_helpers.api_v1_webhook_receive_url(token: webhook_token, host: default_host)
  end

  def regenerate_webhook_token!
    update!(webhook_token: SecureRandom.hex(32))
  end

  ##
  # Resolve instructions for this agent.
  #
  # Priority:
  #   1. Inline instructions (stored on the record, e.g., user override via UI)
  #   2. Prompt file (instructions_prompt path, loaded from app/prompts/)
  #   3. Fallback: generic identity statement
  #
  def resolved_instructions
    if instructions.present?
      instructions
    elsif instructions_prompt.present?
      load_prompt(instructions_prompt)
    else
      "You are #{name}, an AI assistant."
    end
  end

  ##
  # Tool classes this agent should have access to.
  # Returns nil if no custom config (meaning: use defaults).
  #
  def configured_tool_classes
    return nil if tool_config.blank?

    tool_config.filter_map { |name| name.safe_constantize }
  end

  ##
  # Create an agent from a blueprint config hash.
  # Auto-creates the agent's dedicated chat.
  #
  def self.create_from_blueprint!(workspace:, member:, identifier:, **config)
    chat = member.owned_chats.create!(name: config[:name] || identifier.humanize)

    create!(
      workspace: workspace,
      member: member,
      chat: chat,
      identifier: identifier,
      name: config[:name] || identifier.humanize,
      instructions: config[:instructions],
      instructions_prompt: config[:instructions_prompt],
      tool_config: config[:tool_config],
      schedule: config[:schedule],
      metadata: config[:metadata] || {}
    )
  end

  # --- Mentionable ---

  def mentionable_label
    name
  end

  def mentionable_summary
    parts = [name]
    parts << (active? ? "active" : "inactive")
    parts << "scheduled: #{schedule}" if scheduled?
    parts.join(" — ")
  end

  def mentionable_kind
    :agent
  end

  private

  def generate_webhook_token
    self.webhook_token ||= SecureRandom.hex(32)
  end

  def default_host
    ENV.fetch("APPLICATION_URL", "http://localhost:3000").then { |url| URI.parse(url).host }
  end

  def load_prompt(prompt_path)
    # Look for prompt file in app/prompts/ (supports .md and .txt)
    base_path = Rails.root.join("app", "prompts")
    %w[.md .txt .erb].each do |ext|
      full_path = base_path.join("#{prompt_path}#{ext}")
      return File.read(full_path) if File.exist?(full_path)
    end

    # Try without extension
    full_path = base_path.join(prompt_path)
    return File.read(full_path) if File.exist?(full_path)

    Rails.logger.warn "[Agent] Prompt file not found: #{prompt_path} (looked in #{base_path})"
    "You are #{name}, an AI assistant."
  end
end
