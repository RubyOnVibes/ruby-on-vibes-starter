# frozen_string_literal: true

require 'rails_helper'

RSpec.describe AgentTaskJob, type: :job do
  let(:chat) { chats(:alice_personal_chat) }
  let(:workspace) { workspaces(:alice_personal) }
  let(:member) { members(:alice_personal_member) }
  let(:user) { users(:alice) }

  let(:task) do
    AgentTask.create!(
      chat: chat,
      workspace: workspace,
      member: member,
      kind: "test_task"
    )
  end

  # Concrete subclass for testing the base class
  let(:job_class) do
    Class.new(AgentTaskJob) do
      def execute(task)
        { test: "result" }
      end
    end
  end

  describe 'lifecycle' do
    it 'transitions task through pending → running → completed' do
      expect(task).to be_status_pending

      job_class.new.perform(task.id)
      task.reload

      expect(task).to be_status_completed
      expect(task.attempts).to eq(1)
      expect(task.started_at).to be_present
      expect(task.completed_at).to be_present
      expect(task.result).to eq("test" => "result")
    end

    it 'skips already-terminal tasks' do
      task.update!(status: :completed)

      job_class.new.perform(task.id)
      task.reload

      expect(task.attempts).to eq(0) # never incremented
    end

    it 'does not complete if cancelled mid-execution' do
      slow_job = Class.new(AgentTaskJob) do
        def execute(task)
          task.update!(status: :cancelled) # simulate external cancellation
          { should_not: "appear" }
        end
      end

      slow_job.new.perform(task.id)
      task.reload

      expect(task).to be_status_cancelled
      expect(task.result).to eq({})
    end
  end

  describe 'retry logic' do
    let(:failing_job) do
      Class.new(AgentTaskJob) do
        def execute(task)
          raise StandardError, "boom"
        end

        def max_attempts = 3
        def retry_delay(_attempt) = 0.seconds
      end
    end

    it 'retries on failure when under max_attempts' do
      # Stub perform_later since anonymous classes can't be enqueued by SolidQueue
      allow(failing_job).to receive(:set).and_return(double(perform_later: nil))

      expect {
        failing_job.new.perform(task.id)
      }.not_to raise_error

      task.reload
      expect(task).to be_status_pending
      expect(task.attempts).to eq(1)
      expect(task.progress).to eq(0)
      expect(task.progress_text).to match(/Retry 2\/3/)
      expect(task.progress_text).to include("boom")
      expect(failing_job).to have_received(:set).with(wait: 0.seconds)
    end

    it 'fails permanently on final attempt and re-raises' do
      task.update!(attempts: 2) # next will be attempt 3 (final)

      expect {
        failing_job.new.perform(task.id)
      }.to raise_error(StandardError, "boom")

      task.reload
      expect(task).to be_status_failed
      expect(task.error_message).to eq("boom")
      expect(task.completed_at).to be_present
    end
  end

  describe 'effect tracking helpers' do
    let(:job) { job_class.new }

    before do
      # Simulate the perform lifecycle so @task is set
      job.instance_variable_set(:@task, task)
      job.instance_variable_set(:@last_cancel_check, Time.current)
      task.start!
    end

    describe '#track_create' do
      it 'creates a record and logs an effect' do
        expect {
          @ws = job.send(:track_create, Workspace,
            name: "Effect Test WS #{Time.current.to_i}",
            owner: user,
            is_team_workspace: false)
        }.to change { Workspace.count }.by(1)
           .and change { task.effects.count }.by(1)

        expect(@ws).to be_persisted

        effect = task.effects.last
        expect(effect.action).to eq("created")
        expect(effect.target).to eq(@ws)
        expect(effect.description).to include("Workspace")
      end
    end

    describe '#track_update' do
      it 'updates a record and logs changes' do
        ws = Workspace.create!(name: "Before #{Time.current.to_i}", owner: user, is_team_workspace: false)
        new_name = "After #{Time.current.to_i}"

        job.send(:track_update, ws,
          description: "Renamed workspace",
          name: new_name)

        # Verify the record was actually updated
        expect(ws.reload.name).to eq(new_name)

        effect = task.effects.last
        expect(effect.action).to eq("updated")
        expect(effect.target).to eq(ws)
        expect(effect.details["changes"]["name"]["from"]).to start_with("Before")
        expect(effect.details["changes"]["name"]["to"]).to eq(new_name)
      end
    end

    describe '#track_destroy' do
      it 'destroys a record and captures snapshot' do
        ws = Workspace.create!(name: "Doomed #{Time.current.to_i}", owner: user, is_team_workspace: false)
        ws_id = ws.id
        ws_name = ws.name

        expect {
          job.send(:track_destroy, ws, description: "Cleaned up workspace")
        }.to change { Workspace.count }.by(-1)

        effect = task.effects.last
        expect(effect.action).to eq("deleted")
        expect(effect.target_type).to eq("Workspace")
        expect(effect.target_id).to eq(ws_id)
        expect(effect.details["snapshot"]["name"]).to eq(ws_name)
        expect { Workspace.find(ws_id) }.to raise_error(ActiveRecord::RecordNotFound)
      end
    end

    describe '#track_attach' do
      context 'with has_many_attached' do
        it 'attaches a file and logs the effect' do
          csv_content = "test,data\n1,hello\n"

          expect {
            job.send(:track_attach, task, :attachments,
              io: StringIO.new(csv_content),
              filename: "test.csv",
              content_type: "text/csv")
          }.to change { task.attachments.count }.by(1)
             .and change { task.effects.count }.by(1)

          expect(task.attachments.last.filename.to_s).to eq("test.csv")

          effect = task.effects.last
          expect(effect.action).to eq("attached")
          expect(effect.target).to eq(task)
          expect(effect.details["filename"]).to eq("test.csv")
          expect(effect.details["content_type"]).to eq("text/csv")
          expect(effect.details["byte_size"]).to eq(csv_content.bytesize)
        end

        it 'records the correct blob when multiple files exist' do
          # Attach a first file
          task.attachments.attach(
            io: StringIO.new("first"),
            filename: "first.txt",
            content_type: "text/plain"
          )

          # Now track_attach a second file
          job.send(:track_attach, task, :attachments,
            io: StringIO.new("second"),
            filename: "second.txt",
            content_type: "text/plain")

          effect = task.effects.last
          expect(effect.details["filename"]).to eq("second.txt")
        end
      end

      context 'with has_one_attached' do
        it 'attaches a file and logs the effect' do
          ws = Workspace.create!(name: "Avatar Test #{Time.current.to_i}", owner: user, is_team_workspace: false)
          png_data = "fake-png-data"

          job.send(:track_attach, ws, :avatar,
            io: StringIO.new(png_data),
            filename: "avatar.png",
            content_type: "image/png")

          expect(ws.avatar).to be_attached
          expect(ws.avatar.filename.to_s).to eq("avatar.png")

          effect = task.effects.last
          expect(effect.action).to eq("attached")
          expect(effect.target).to eq(ws)
          expect(effect.details["filename"]).to eq("avatar.png")
          expect(effect.details["content_type"]).to eq("image/png")
          expect(effect.details["byte_size"]).to eq(png_data.bytesize)
        end
      end
    end

    describe '#track_detach' do
      context 'with has_many_attached' do
        it 'detaches by filename and logs the effect' do
          task.attachments.attach(
            io: StringIO.new("temporary"),
            filename: "temp.txt",
            content_type: "text/plain"
          )

          expect {
            job.send(:track_detach, task, :attachments, "temp.txt")
          }.to change { task.attachments.reload.count }.from(1).to(0)

          effect = task.effects.last
          expect(effect.action).to eq("detached")
          expect(effect.target).to eq(task)
          expect(effect.details["filename"]).to eq("temp.txt")
          expect(effect.details["content_type"]).to eq("text/plain")
        end

        it 'raises when filename not found' do
          expect {
            job.send(:track_detach, task, :attachments, "nonexistent.txt")
          }.to raise_error(ActiveRecord::RecordNotFound)
        end

        it 'detaches only the named file when multiple exist' do
          task.attachments.attach(
            io: StringIO.new("keep me"),
            filename: "keep.txt",
            content_type: "text/plain"
          )
          task.attachments.attach(
            io: StringIO.new("remove me"),
            filename: "remove.txt",
            content_type: "text/plain"
          )

          job.send(:track_detach, task, :attachments, "remove.txt")

          remaining = task.attachments.reload
          expect(remaining.count).to eq(1)
          expect(remaining.first.filename.to_s).to eq("keep.txt")
        end
      end

      context 'with has_one_attached' do
        it 'detaches and logs the effect' do
          ws = Workspace.create!(name: "Detach Test #{Time.current.to_i}", owner: user, is_team_workspace: false)
          ws.avatar.attach(
            io: StringIO.new("fake-png"),
            filename: "old_avatar.png",
            content_type: "image/png"
          )
          expect(ws.avatar).to be_attached

          job.send(:track_detach, ws, :avatar)

          ws.reload
          expect(ws.avatar).not_to be_attached

          effect = task.effects.last
          expect(effect.action).to eq("detached")
          expect(effect.target).to eq(ws)
          expect(effect.details["filename"]).to eq("old_avatar.png")
          expect(effect.details["content_type"]).to eq("image/png")
        end

        it 'raises when nothing attached' do
          ws = Workspace.create!(name: "Empty Avatar #{Time.current.to_i}", owner: user, is_team_workspace: false)

          expect {
            job.send(:track_detach, ws, :avatar)
          }.to raise_error(ActiveRecord::RecordNotFound, /No attachment/)
        end
      end
    end

    describe '#track_effect' do
      it 'logs a custom effect with a target' do
        job.send(:track_effect, "notified",
          target: user,
          description: "Sent email notification",
          details: { channel: "email", recipient: user.email })

        effect = task.effects.last
        expect(effect.action).to eq("notified")
        expect(effect.target).to eq(user)
        expect(effect.description).to eq("Sent email notification")
        expect(effect.details["channel"]).to eq("email")
        expect(effect.details["recipient"]).to eq(user.email)
      end

      it 'logs a custom effect without a target' do
        job.send(:track_effect, "custom",
          description: "Called external API",
          details: { url: "https://api.example.com" })

        effect = task.effects.last
        expect(effect.action).to eq("custom")
        expect(effect.target).to be_nil
        expect(effect.description).to eq("Called external API")
      end
    end

    describe '#track_enqueue_subtask' do
      it 'creates a subtask linked to the parent and logs an enqueued effect' do
        subtask = job.send(:track_enqueue_subtask, Examples::EchoAgentTaskJob,
          kind: "echo_test",
          description: "Spawned echo subtask",
          metadata: { message: "test", duration: 1 })

        expect(subtask).to be_persisted
        expect(subtask.parent_task).to eq(task)
        expect(subtask.chat).to eq(task.chat)
        expect(subtask.workspace).to eq(task.workspace)
        expect(subtask.member).to eq(task.member)
        expect(subtask.kind).to eq("echo_test")
        expect(subtask.metadata).to eq("message" => "test", "duration" => 1)
        expect(subtask).to be_status_pending

        effect = task.effects.last
        expect(effect.action).to eq("enqueued")
        expect(effect.target).to eq(subtask)
        expect(effect.description).to eq("Spawned echo subtask")
        expect(effect.details["subtask_id"]).to eq(subtask.to_param)
        expect(effect.details["job_class"]).to eq("Examples::EchoAgentTaskJob")
        expect(effect.details["kind"]).to eq("echo_test")
      end

      it 'uses a default description when none provided' do
        subtask = job.send(:track_enqueue_subtask, Examples::EchoAgentTaskJob,
          kind: "data_export")

        effect = task.effects.last
        expect(effect.description).to eq("Enqueued Data export subtask")
      end

      it 'is visible via the parent task subtasks association' do
        subtask = job.send(:track_enqueue_subtask, Examples::EchoAgentTaskJob,
          kind: "echo_test",
          metadata: { duration: 1 })

        expect(task.subtasks.reload).to include(subtask)
      end
    end

    describe 'transactional atomicity' do
      it 'rolls back the record if effect creation fails' do
        # Stub effects.create! to fail after the record is created
        allow(task.effects).to receive(:create!).and_raise(ActiveRecord::RecordInvalid)

        expect {
          job.send(:track_create, Workspace,
            name: "Should Roll Back #{Time.current.to_i}",
            owner: user,
            is_team_workspace: false) rescue nil
        }.not_to change { Workspace.count }
      end
    end
  end
end
