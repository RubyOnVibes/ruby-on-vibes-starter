# frozen_string_literal: true

require 'rails_helper'

RSpec.describe AgentProvisioner do
  let(:workspace) { workspaces(:alice_personal) }
  let(:owner_member) { members(:alice_personal_member) }

  let(:manager_blueprints) do
    {
      "default" => {
        "manager" => { "name" => "Manager", "instructions_prompt" => "agents/manager" }
      }
    }
  end

  before do
    allow(RubyOnVibes).to receive(:agents?).and_return(true)
    AgentProvisioner.send(:instance_variable_set, :@config, nil)
    allow(YAML).to receive(:load_file).and_return(manager_blueprints)
  end

  describe '.provision!' do
    it 'creates agents from default blueprints' do
      expect {
        AgentProvisioner.provision!(workspace)
      }.to change { workspace.agents.reload.count }.from(0)

      agent = workspace.agents.find_by(identifier: "manager")
      expect(agent).to be_present
      expect(agent.name).to eq("Manager")
      expect(agent.member).to eq(owner_member)
      expect(agent.chat).to be_present
      expect(agent.instructions_prompt).to eq("agents/manager")
    end

    it 'is idempotent — does not duplicate existing agents' do
      AgentProvisioner.provision!(workspace)

      expect {
        AgentProvisioner.provision!(workspace)
      }.not_to change { workspace.agents.count }
    end

    it 'creates only missing agents when some exist' do
      AgentProvisioner.provision!(workspace)

      # Simulate adding a new blueprint
      blueprints = {
        "default" => {
          "manager" => { "name" => "Manager", "instructions_prompt" => "agents/manager" },
          "reporter" => { "name" => "Reporter", "instructions_prompt" => "agents/manager" }
        }
      }
      allow(YAML).to receive(:load_file).and_return(blueprints)
      AgentProvisioner.send(:instance_variable_set, :@config, nil) # clear cache

      expect {
        AgentProvisioner.provision!(workspace)
      }.to change { workspace.agents.count }.by(1)

      expect(workspace.agents.find_by(identifier: "reporter")).to be_present
    end

    it 'skips provisioning when agents feature is disabled' do
      allow(RubyOnVibes).to receive(:agents?).and_return(false)

      expect {
        AgentProvisioner.provision!(workspace)
      }.not_to change { Agent.count }
    end

    it 'handles missing blueprint config gracefully' do
      allow(File).to receive(:exist?).and_call_original
      allow(File).to receive(:exist?).with(Rails.root.join("config", "agent_blueprints.yml")).and_return(false)
      AgentProvisioner.send(:instance_variable_set, :@config, nil)

      expect {
        AgentProvisioner.provision!(workspace)
      }.not_to change { Agent.count }
    end
  end
end
