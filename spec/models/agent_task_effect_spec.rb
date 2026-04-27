# frozen_string_literal: true

require 'rails_helper'

RSpec.describe AgentTaskEffect, type: :model do
  let(:chat) { chats(:alice_personal_chat) }
  let(:workspace) { workspaces(:alice_personal) }
  let(:member) { members(:alice_personal_member) }

  let(:task) do
    AgentTask.create!(
      chat: chat,
      workspace: workspace,
      member: member,
      kind: "test_task"
    )
  end

  def create_effect!(action: "created", **attrs)
    task.effects.create!(
      action: action,
      description: "Test #{action} effect",
      **attrs
    )
  end

  describe 'validations' do
    it 'requires a valid action' do
      effect = task.effects.build(action: "invalid", description: "test")
      expect(effect).not_to be_valid
      expect(effect.errors[:action]).to be_present
    end

    it 'accepts all defined actions' do
      AgentTaskEffect::ACTIONS.each do |action|
        effect = task.effects.build(action: action, description: "test")
        expect(effect).to be_valid, "Expected '#{action}' to be valid"
      end
    end

    it 'requires description' do
      effect = task.effects.build(action: "created")
      expect(effect).not_to be_valid
      expect(effect.errors[:description]).to be_present
    end
  end

  describe 'associations' do
    it 'belongs to agent_task' do
      effect = create_effect!
      expect(effect.agent_task).to eq(task)
    end

    it 'supports polymorphic target' do
      effect = create_effect!(target: workspace)
      expect(effect.target).to eq(workspace)
      expect(effect.target_type).to eq("Workspace")
    end

    it 'allows nil target (for deleted records or custom effects)' do
      effect = create_effect!(target: nil)
      expect(effect).to be_valid
      expect(effect.target).to be_nil
    end
  end

  describe 'scopes' do
    it '.for_record filters by polymorphic target' do
      ws_effect = create_effect!(target: workspace)
      other_effect = create_effect!(target: member)

      results = AgentTaskEffect.for_record(workspace)
      expect(results).to include(ws_effect)
      expect(results).not_to include(other_effect)
    end

    it '.mutations returns created, updated, deleted' do
      created = create_effect!(action: "created")
      updated = create_effect!(action: "updated")
      deleted = create_effect!(action: "deleted")
      attached = create_effect!(action: "attached")

      mutations = task.effects.mutations
      expect(mutations).to include(created, updated, deleted)
      expect(mutations).not_to include(attached)
    end

    it '.attachments returns attached and detached' do
      attached = create_effect!(action: "attached")
      detached = create_effect!(action: "detached")
      created = create_effect!(action: "created")

      attachments = task.effects.attachments
      expect(attachments).to include(attached, detached)
      expect(attachments).not_to include(created)
    end

    it '.by_recency orders by created_at ascending' do
      first = create_effect!(action: "created")
      second = create_effect!(action: "updated")

      expect(task.effects.by_recency.to_a).to eq([first, second])
    end
  end

  describe 'details' do
    it 'stores arbitrary JSON details' do
      effect = create_effect!(
        action: "updated",
        details: { changes: { name: { from: "Old", to: "New" } } }
      )

      effect.reload
      expect(effect.details["changes"]["name"]["from"]).to eq("Old")
      expect(effect.details["changes"]["name"]["to"]).to eq("New")
    end
  end
end
