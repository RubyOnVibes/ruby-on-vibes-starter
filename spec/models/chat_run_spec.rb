# frozen_string_literal: true

require 'rails_helper'

RSpec.describe ChatRun, type: :model do
  let(:chat) { chats(:team_chat) }

  before do
    # Stub broadcasts to avoid partial render errors in tests
    allow(Turbo::StreamsChannel).to receive(:broadcast_replace_to)
  end

  def create_run!(status: :pending, **attrs)
    chat.chat_runs.create!(status: status, **attrs)
  end

  describe 'status helpers' do
    it '#active? returns true for pending and running' do
      run = create_run!(status: :pending)
      expect(run).to be_active

      run.update!(status: :running)
      expect(run).to be_active
    end

    it '#active? returns false for terminal states' do
      run = create_run!(status: :completed)
      expect(run).not_to be_active
    end

    it '#stopping? returns true for cancelled and failed' do
      run = create_run!(status: :cancelled)
      expect(run).to be_stopping

      run2 = create_run!(status: :failed)
      expect(run2).to be_stopping
    end
  end

  describe 'timestamp callbacks' do
    it 'sets completed_at when completing' do
      run = create_run!(status: :running)
      run.update!(status: :completed)

      expect(run.completed_at).to be_present
    end

    it 'sets cancelled_at when cancelling' do
      run = create_run!(status: :running)
      run.update!(status: :cancelled)

      expect(run.cancelled_at).to be_present
    end

    it 'sets failed_at when failing' do
      run = create_run!(status: :running)
      run.update!(status: :failed)

      expect(run.failed_at).to be_present
    end
  end

  describe '#ended_at' do
    it 'returns completed_at for completed runs' do
      run = create_run!(status: :running)
      run.update!(status: :completed)

      expect(run.ended_at).to eq(run.completed_at)
    end

    it 'returns cancelled_at for cancelled runs' do
      run = create_run!(status: :running)
      run.update!(status: :cancelled)

      expect(run.ended_at).to eq(run.cancelled_at)
    end

    it 'falls back to updated_at' do
      run = create_run!(status: :running)
      expect(run.ended_at).to eq(run.updated_at)
    end
  end

  describe '#cancel!' do
    context 'when pending' do
      it 'transitions to cancelled' do
        run = create_run!(status: :pending)
        result = run.cancel!

        expect(result).to be true
        run.reload
        expect(run).to be_status_cancelled
        expect(run.cancelled_at).to be_present
      end
    end

    context 'when running with an assistant message' do
      it 'clears the processing message content' do
        run = create_run!(status: :running)

        # Create an assistant message during this run
        msg = chat.messages.create!(
          role: :assistant,
          content: "Partial response being streamed...",
          user_submitted: false,
          created_at: run.created_at + 1.second
        )

        # Stub broadcast
        allow(msg).to receive(:broadcast_full_replace!)
        allow_any_instance_of(Message).to receive(:broadcast_full_replace!)

        run.cancel!

        msg.reload
        expect(msg.content).to eq("")
        expect(msg.metadata['cancelled']).to be true
      end
    end

    context 'when running with orphaned tool calls' do
      it 'destroys orphaned tool calls on the processing message' do
        run = create_run!(status: :running)

        msg = chat.messages.create!(
          role: :assistant,
          content: "",
          user_submitted: false,
          created_at: run.created_at + 1.second
        )
        allow_any_instance_of(Message).to receive(:broadcast_full_replace!)

        # Create tool calls on the assistant message
        tc = ToolCall.create!(
          message: msg,
          tool_call_id: "call_abc123",
          name: "search",
          arguments: "{}"
        )

        run.cancel!

        expect { tc.reload }.to raise_error(ActiveRecord::RecordNotFound)
      end
    end

    context 'when already completed' do
      it 'returns true without changes (no-op)' do
        run = create_run!(status: :completed)
        original_updated_at = run.updated_at

        result = run.cancel!

        expect(result).to be true
        expect(run.reload.updated_at).to eq(original_updated_at)
      end
    end

    context 'when already cancelled' do
      it 'returns true without changes (no-op)' do
        run = create_run!(status: :cancelled)

        result = run.cancel!
        expect(result).to be true
      end
    end
  end

  describe 'scopes' do
    it '.active returns pending and running runs' do
      pending_run = create_run!(status: :pending)
      completed_run = create_run!(status: :completed)

      active = chat.chat_runs.active
      expect(active).to include(pending_run)
      expect(active).not_to include(completed_run)
    end
  end

  describe 'node_name' do
    it 'captures hostname on creation' do
      run = create_run!
      expect(run.node_name).to be_present
    end
  end
end
