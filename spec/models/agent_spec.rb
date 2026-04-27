# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Agent, type: :model do
  let(:chat) { chats(:alice_personal_chat) }
  let(:workspace) { workspaces(:alice_personal) }
  let(:member) { members(:alice_personal_member) }

  def create_agent!(identifier: "test_agent", **attrs)
    agent_chat = Chat.create!(member: member, name: "Agent Chat")
    Agent.create!(
      workspace: workspace,
      member: member,
      chat: agent_chat,
      name: "Test Agent",
      identifier: identifier,
      **attrs
    )
  end

  describe 'validations' do
    it 'requires name' do
      agent = Agent.new(workspace: workspace, member: member, chat: chat, identifier: "valid")
      expect(agent).not_to be_valid
      expect(agent.errors[:name]).to be_present
    end

    it 'requires identifier' do
      agent = Agent.new(workspace: workspace, member: member, chat: chat, name: "Test")
      expect(agent).not_to be_valid
      expect(agent.errors[:identifier]).to be_present
    end

    it 'requires identifier to be lowercase with underscores' do
      agent = Agent.new(workspace: workspace, member: member, chat: chat, name: "Test", identifier: "Invalid-Id!")
      expect(agent).not_to be_valid
      expect(agent.errors[:identifier]).to be_present
    end

    it 'accepts valid identifier format' do
      agent = create_agent!(identifier: "my_reporting_agent_v2")
      expect(agent).to be_valid
    end

    it 'enforces identifier uniqueness per workspace' do
      create_agent!(identifier: "unique_agent")
      expect {
        create_agent!(identifier: "unique_agent")
      }.to raise_error(ActiveRecord::RecordInvalid, /Identifier has already been taken/)
    end

    it 'allows same identifier in different workspaces' do
      create_agent!(identifier: "shared_name")

      bob_workspace = workspaces(:bob_personal)
      bob_member = members(:bob_personal_member)
      bob_chat = Chat.create!(member: bob_member, name: "Bob Agent Chat")

      agent2 = Agent.new(
        workspace: bob_workspace, member: bob_member, chat: bob_chat,
        name: "Test", identifier: "shared_name"
      )
      expect(agent2).to be_valid
    end
  end

  describe 'associations' do
    it 'belongs to workspace, member, and chat' do
      agent = create_agent!
      expect(agent.workspace).to eq(workspace)
      expect(agent.member).to eq(member)
      expect(agent.chat).to be_present
    end
  end

  describe 'webhook_token' do
    it 'auto-generates webhook_token on create' do
      agent = create_agent!
      expect(agent.webhook_token).to be_present
      expect(agent.webhook_token.length).to eq(64) # 32 bytes hex
    end

    it 'regenerates webhook_token' do
      agent = create_agent!
      old_token = agent.webhook_token

      agent.regenerate_webhook_token!
      expect(agent.webhook_token).not_to eq(old_token)
      expect(agent.webhook_token.length).to eq(64)
    end
  end

  describe '#scheduled?' do
    it 'returns true when schedule is present' do
      agent = create_agent!(schedule: "0 9 * * 1-5")
      expect(agent).to be_scheduled
    end

    it 'returns false when schedule is blank' do
      agent = create_agent!
      expect(agent).not_to be_scheduled
    end
  end

  describe '#resolved_instructions' do
    it 'returns inline instructions when present' do
      agent = create_agent!(instructions: "Be a good agent.")
      expect(agent.resolved_instructions).to eq("Be a good agent.")
    end

    it 'loads from prompt file when instructions_prompt set' do
      agent = create_agent!(instructions_prompt: "agents/manager")
      resolved = agent.resolved_instructions
      expect(resolved).to include("Manager")
    end

    it 'prefers inline instructions over prompt file' do
      agent = create_agent!(
        instructions: "Inline wins",
        instructions_prompt: "agents/manager"
      )
      expect(agent.resolved_instructions).to eq("Inline wins")
    end

    it 'falls back to generic identity when nothing set' do
      agent = create_agent!
      expect(agent.resolved_instructions).to eq("You are Test Agent, an AI assistant.")
    end
  end

  describe '#configured_tool_classes' do
    it 'returns nil when tool_config is blank' do
      agent = create_agent!
      expect(agent.configured_tool_classes).to be_nil
    end

    it 'resolves tool class names to classes' do
      agent = create_agent!(tool_config: ["CurrentDateTimeTool", "WebFetchTool"])
      expect(agent.configured_tool_classes).to eq([CurrentDateTimeTool, WebFetchTool])
    end

    it 'skips invalid class names' do
      agent = create_agent!(tool_config: ["CurrentDateTimeTool", "NonexistentTool"])
      expect(agent.configured_tool_classes).to eq([CurrentDateTimeTool])
    end
  end

  describe '.create_from_blueprint!' do
    it 'creates agent with a new chat' do
      agent = Agent.create_from_blueprint!(
        workspace: workspace,
        member: member,
        identifier: "blueprint_agent",
        name: "Blueprint Agent",
        instructions_prompt: "agents/manager"
      )

      expect(agent).to be_persisted
      expect(agent.identifier).to eq("blueprint_agent")
      expect(agent.chat).to be_persisted
      expect(agent.chat.name).to eq("Blueprint Agent")
      expect(agent.instructions_prompt).to eq("agents/manager")
    end
  end

  describe 'scopes' do
    it '.active returns only active agents' do
      active = create_agent!(identifier: "active_one")
      inactive = create_agent!(identifier: "inactive_one", active: false)

      expect(Agent.active).to include(active)
      expect(Agent.active).not_to include(inactive)
    end

    it '.scheduled returns active agents with schedules' do
      scheduled = create_agent!(identifier: "sched", schedule: "0 9 * * *")
      unscheduled = create_agent!(identifier: "unsched")
      inactive_scheduled = create_agent!(identifier: "inactive_sched", schedule: "0 9 * * *", active: false)

      expect(Agent.scheduled).to include(scheduled)
      expect(Agent.scheduled).not_to include(unscheduled, inactive_scheduled)
    end
  end

  describe 'mentionable' do
    it 'returns formatted label and summary' do
      agent = create_agent!(schedule: "0 9 * * 1-5")

      expect(agent.mentionable_label).to eq("Test Agent")
      expect(agent.mentionable_summary).to include("Test Agent")
      expect(agent.mentionable_summary).to include("active")
      expect(agent.mentionable_summary).to include("scheduled")
      expect(agent.mentionable_kind).to eq(:agent)
    end
  end
end
