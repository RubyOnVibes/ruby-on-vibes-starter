# frozen_string_literal: true

require 'rails_helper'

RSpec.describe AgentTask, type: :model do
  let(:chat) { chats(:alice_personal_chat) }
  let(:workspace) { workspaces(:alice_personal) }
  let(:member) { members(:alice_personal_member) }

  def create_task!(status: :pending, **attrs)
    AgentTask.create!(
      chat: chat,
      workspace: workspace,
      member: member,
      kind: "test_task",
      **attrs,
      status: status
    )
  end

  describe 'validations' do
    it 'requires kind' do
      task = AgentTask.new(chat: chat, workspace: workspace, member: member)
      expect(task).not_to be_valid
      expect(task.errors[:kind]).to be_present
    end

    it 'requires kind to be lowercase with underscores' do
      task = AgentTask.new(chat: chat, workspace: workspace, member: member, kind: "Invalid-Kind!")
      expect(task).not_to be_valid
      expect(task.errors[:kind]).to be_present
    end

    it 'accepts valid kind format' do
      task = create_task!(kind: "customer_analysis")
      expect(task).to be_valid
    end
  end

  describe 'associations' do
    it 'belongs to chat, workspace, and member' do
      task = create_task!
      expect(task.chat).to eq(chat)
      expect(task.workspace).to eq(workspace)
      expect(task.member).to eq(member)
    end

    it 'has many effects' do
      task = create_task!
      effect = task.effects.create!(action: "created", description: "Test effect")
      expect(task.effects).to include(effect)
    end

    it 'supports parent_task / subtasks' do
      parent = create_task!
      child = create_task!(parent_task: parent)

      expect(child.parent_task).to eq(parent)
      expect(parent.subtasks).to include(child)
    end

    it 'nullifies subtasks on destroy' do
      parent = create_task!
      child = create_task!(parent_task: parent)

      parent.destroy!
      expect(child.reload.parent_task_id).to be_nil
    end

    it 'destroys effects on destroy' do
      task = create_task!
      effect = task.effects.create!(action: "created", description: "Test")

      task.destroy!
      expect { effect.reload }.to raise_error(ActiveRecord::RecordNotFound)
    end
  end

  describe 'status helpers' do
    it '#active? returns true for pending and running' do
      task = create_task!(status: :pending)
      expect(task).to be_active

      task.update!(status: :running)
      expect(task).to be_active
    end

    it '#active? returns false for terminal states' do
      task = create_task!(status: :completed)
      expect(task).not_to be_active
    end

    it '#terminal? returns true for completed, cancelled, failed' do
      %i[completed cancelled failed].each do |status|
        task = create_task!(status: status)
        expect(task).to be_terminal
      end
    end

    it '#terminal? returns false for active states' do
      %i[pending running].each do |status|
        task = create_task!(status: status)
        expect(task).not_to be_terminal
      end
    end
  end

  describe '#start!' do
    it 'transitions to running and sets started_at' do
      task = create_task!
      task.start!

      expect(task).to be_status_running
      expect(task.started_at).to be_present
    end

    it 'does not overwrite started_at on re-start (retry)' do
      task = create_task!
      task.start!
      original = task.started_at

      task.update!(status: :pending)
      task.start!

      expect(task.started_at).to eq(original)
    end
  end

  describe '#update_progress!' do
    it 'sets progress and progress_text' do
      task = create_task!(status: :running)
      task.update_progress!(50, "Halfway there")

      expect(task.progress).to eq(50)
      expect(task.progress_text).to eq("Halfway there")
    end
  end

  describe '#complete!' do
    it 'transitions to completed with result' do
      task = create_task!(status: :running)
      task.complete!({ answer: 42 })

      expect(task).to be_status_completed
      expect(task.progress).to eq(100)
      expect(task.result).to eq("answer" => 42)
      expect(task.completed_at).to be_present
    end
  end

  describe '#fail!' do
    it 'transitions to failed with error message' do
      task = create_task!(status: :running)
      task.fail!("Something went wrong")

      expect(task).to be_status_failed
      expect(task.error_message).to eq("Something went wrong")
      expect(task.progress_text).to eq("Failed")
      expect(task.completed_at).to be_present
    end

    it 'includes attempt count when retried' do
      task = create_task!(status: :running, attempts: 3)
      task.fail!("Gave up")

      expect(task.progress_text).to eq("Failed after 3 attempts")
    end
  end

  describe '#cancel!' do
    it 'cancels active tasks' do
      task = create_task!(status: :running)
      result = task.cancel!

      expect(result).to be true
      expect(task).to be_status_cancelled
      expect(task.completed_at).to be_present
    end

    it 'returns false for terminal tasks' do
      task = create_task!(status: :completed)
      expect(task.cancel!).to be false
    end

    it 'cascades cancellation to active subtasks' do
      parent = create_task!(status: :running)
      active_child = create_task!(status: :running, parent_task: parent)
      pending_child = create_task!(status: :pending, parent_task: parent)
      completed_child = create_task!(status: :completed, parent_task: parent)

      parent.cancel!

      expect(active_child.reload).to be_status_cancelled
      expect(pending_child.reload).to be_status_cancelled
      expect(completed_child.reload).to be_status_completed # untouched
    end

    it 'cascades recursively through nested subtasks' do
      grandparent = create_task!(status: :running)
      parent = create_task!(status: :running, parent_task: grandparent)
      child = create_task!(status: :pending, parent_task: parent)

      grandparent.cancel!

      expect(parent.reload).to be_status_cancelled
      expect(child.reload).to be_status_cancelled
    end
  end

  describe '#await_approval!' do
    it 'transitions to awaiting_approval with result' do
      task = create_task!(status: :running)
      task.await_approval!({ proposed: "action" })

      expect(task).to be_status_awaiting_approval
      expect(task.result).to eq("proposed" => "action")
    end
  end

  describe 'scopes' do
    it '.active returns pending and running tasks' do
      pending_task = create_task!(status: :pending)
      running_task = create_task!(status: :running)
      completed_task = create_task!(status: :completed)

      active = AgentTask.active
      expect(active).to include(pending_task, running_task)
      expect(active).not_to include(completed_task)
    end

    it '.terminal returns completed, cancelled, and failed tasks' do
      completed = create_task!(status: :completed)
      cancelled = create_task!(status: :cancelled)
      pending_task = create_task!(status: :pending)

      terminal = AgentTask.terminal
      expect(terminal).to include(completed, cancelled)
      expect(terminal).not_to include(pending_task)
    end

    it '.recent_completed returns tasks completed in last 24 hours' do
      recent = create_task!(status: :completed)
      recent.update_column(:completed_at, 1.hour.ago)

      old = create_task!(status: :completed)
      old.update_column(:completed_at, 2.days.ago)

      expect(AgentTask.recent_completed).to include(recent)
      expect(AgentTask.recent_completed).not_to include(old)
    end
  end

  describe 'mentionable' do
    it 'returns formatted label and summary' do
      task = create_task!(kind: "customer_analysis")

      expect(task.mentionable_label).to include("Customer analysis")
      expect(task.mentionable_summary).to include("Customer analysis")
      expect(task.mentionable_kind).to eq("agent_task")
    end
  end
end
