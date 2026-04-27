# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Examples::SideEffectsExerciseJob, type: :job do
  let(:chat) { chats(:alice_personal_chat) }
  let(:workspace) { workspaces(:alice_personal) }
  let(:member) { members(:alice_personal_member) }

  let(:task) do
    AgentTask.create!(
      chat: chat,
      workspace: workspace,
      member: member,
      kind: "side_effects_exercise",
      metadata: { "step_delay" => 0 } # no sleeps in tests
    )
  end

  # Run the job once and share the result across the "full run" context
  shared_context 'completed exercise' do
    before do
      described_class.new.perform(task.id)
      task.reload
    end
  end

  describe 'full run' do
    include_context 'completed exercise'

    it 'completes successfully with all 10 effects' do
      expect(task).to be_status_completed
      expect(task.progress).to eq(100)
      expect(task.result["effects_completed"]).to eq(10)
      expect(task.result["effects_exercised"]).to contain_exactly(
        "created", "updated", "attached_has_one", "detached_has_one",
        "attached_has_many", "detached_has_many", "notified",
        "enqueued_subtask", "deleted"
      )
    end

    it 'logs all 10 effects in the correct order' do
      effects = task.effects.by_recency.to_a
      expect(effects.length).to eq(10)
      expect(effects.map(&:action)).to eq(%w[
        created updated attached detached
        attached attached detached
        notified enqueued deleted
      ])
    end

    it 'creates and destroys the exercise workspace (no leftovers)' do
      delete_effect = task.effects.find_by(action: "deleted")
      create_effect = task.effects.find_by(action: "created")

      expect(delete_effect.target_type).to eq("Workspace")
      expect(delete_effect.target_id).to eq(create_effect.target_id)
      expect { Workspace.find(create_effect.target_id) }.to raise_error(ActiveRecord::RecordNotFound)
    end

    it 'leaves the CSV attachment on the task (TXT was detached)' do
      expect(task.attachments.count).to eq(1)
      expect(task.attachments.first.filename.to_s).to eq("exercise_data.csv")
    end

    describe 'subtask' do
      it 'creates an echo subtask linked to the parent task' do
        subtask_id = task.result["subtask_id"]
        expect(subtask_id).to be_present

        subtask = AgentTask.find_by_prefix_id(subtask_id)
        expect(subtask).to be_present
        expect(subtask.parent_task).to eq(task)
        expect(subtask.chat).to eq(task.chat)
        expect(subtask.workspace).to eq(task.workspace)
        expect(subtask.kind).to eq("echo_test")
        expect(subtask.metadata["message"]).to include("subtask")
      end

      it 'logs the enqueued effect targeting the subtask' do
        enqueued_effect = task.effects.find_by(action: "enqueued")

        expect(enqueued_effect).to be_present
        expect(enqueued_effect.target_type).to eq("AgentTask")
        expect(enqueued_effect.details["job_class"]).to eq("Examples::EchoAgentTaskJob")
        expect(enqueued_effect.details["kind"]).to eq("echo_test")
        expect(enqueued_effect.details["subtask_id"]).to be_present
      end

      it 'is visible via the parent task subtasks association' do
        expect(task.subtasks.count).to eq(1)
        expect(task.subtasks.first.kind).to eq("echo_test")
      end
    end

    describe 'effect details' do
      it 'captures workspace name changes in the update effect' do
        update_effect = task.effects.find_by(action: "updated")
        changes = update_effect.details["changes"]["name"]

        expect(changes["from"]).to start_with("Exercise")
        expect(changes["from"]).not_to include("(updated)")
        expect(changes["to"]).to include("(updated)")
      end

      it 'captures the workspace snapshot in the destroy effect' do
        delete_effect = task.effects.find_by(action: "deleted")

        expect(delete_effect.details["snapshot"]).to be_present
        expect(delete_effect.details["snapshot"]["name"]).to include("(updated)")
        expect(delete_effect.details["snapshot"]["is_team_workspace"]).to be false
      end

      it 'records correct metadata for all attachment effects' do
        attach_effects = task.effects.where(action: "attached").order(:id)
        detach_effects = task.effects.where(action: "detached").order(:id)

        # 3 attaches: avatar (has_one), CSV (has_many), TXT (has_many)
        expect(attach_effects.length).to eq(3)
        expect(attach_effects[0].details).to include("filename" => "exercise_avatar.png", "content_type" => "image/png")
        expect(attach_effects[1].details).to include("filename" => "exercise_data.csv", "content_type" => "text/csv")
        expect(attach_effects[2].details).to include("filename" => "exercise_temp.txt", "content_type" => "text/plain")

        attach_effects.each do |effect|
          expect(effect.details["byte_size"]).to be > 0
        end

        # 2 detaches: avatar (has_one), TXT (has_many)
        expect(detach_effects.length).to eq(2)
        expect(detach_effects[0].details["filename"]).to eq("exercise_avatar.png")
        expect(detach_effects[1].details["filename"]).to eq("exercise_temp.txt")
      end

      it 'records the notified effect targeting the user' do
        notified = task.effects.find_by(action: "notified")

        expect(notified.target_type).to eq("User")
        expect(notified.target_id).to eq(member.user_id)
        expect(notified.details["channel"]).to eq("email")
        expect(notified.details["subject"]).to include("exercise")
      end
    end
  end

  describe 'cleanup on cancellation' do
    it 'destroys the exercise workspace when cancelled after creation' do
      initial_ws_count = Workspace.count

      call_count = 0
      allow_any_instance_of(described_class).to receive(:cancelled?) do
        call_count += 1
        call_count > 1
      end

      described_class.new.perform(task.id)
      task.reload

      expect(Workspace.count).to eq(initial_ws_count)
      expect(task.result["cancelled"]).to be true
      expect(task.result["effects_completed"]).to be < 10
    end
  end
end
