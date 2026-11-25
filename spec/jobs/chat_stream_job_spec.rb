# frozen_string_literal: true

require "rails_helper"
require "ruby_llm/test_helper"

RSpec.describe ChatStreamJob, type: :job do
  include RubyLLM::TestHelper
  let(:chat) { chats(:alice_personal_chat) }
  let(:member) { members(:alice_personal_member) }

  before do
    chat.chat_runs.delete_all
    chat.messages.destroy_all
    allow(Turbo::StreamsChannel).to receive(:broadcast_action_to)
    allow(Turbo::StreamsChannel).to receive(:broadcast_replace_to)
    allow(Turbo::StreamsChannel).to receive(:broadcast_append_to)
    allow_any_instance_of(ToolsetService).to receive(:tool_classes).and_return([Examples::RenameChatTool])
  end

  def new_run
    input = chat.messages.create!(role: :user, content: "Rename it", member: member, user: member.user)
    chat.chat_runs.create!(input_message: input, initiated_by_member: member)
  end

  it "keeps provider and infrastructure exception details out of the transcript" do
    run = new_run
    allow_any_instance_of(Chat).to receive(:complete).and_raise(RuntimeError, "secret-key-and-private-path")
    expect { described_class.perform_now(run.id) }.to raise_error(RuntimeError)
    expect(run.reload).to be_status_failed
    expect(chat.messages.where(role: :assistant).sole.content).not_to include("secret-key", "private-path")
  end

  it "rechecks the initiating member after model generation and before a tool runs" do
    run = new_run
    tool = Class.new(RubyLLM::Tool) do
      description "Write a business record"
      def initialize(**); end
      def execute = raise("This effect must never execute")
    end
    stub_const("RevokedEffectTool", tool)
    allow_any_instance_of(ToolsetService).to receive(:tool_classes).and_return([RevokedEffectTool])
    stub_replies tool_call(:revoked_effect), "Finished"
    allow_any_instance_of(RubyLLM::Providers::Anthropic).to receive(:complete).and_wrap_original do |original, *args, **kwargs, &block|
      result = original.call(*args, **kwargs, &block)
      chat.chat_members.where(member: member).delete_all
      result
    end
    expect { described_class.perform_now(run.id) }.to raise_error(Pundit::NotAuthorizedError)
    expect(run.reload).to be_status_failed
    expect(chat.messages.where(role: :tool).pluck(:content).join).not_to include("Finished")
  end

  it "leaves persisted dispatch intent recoverable when enqueueing fails" do
    run = new_run
    allow(described_class).to receive(:perform_later).and_raise(ActiveJob::EnqueueError)
    expect(run.dispatch!).to be false
    expect(run.reload.resume_at).to be_present
    allow(described_class).to receive(:perform_later)
    ResumeChatRunsJob.perform_now
    expect(described_class).to have_received(:perform_later).with(run.id).twice
  end

  it "keeps a native task recoverable when scheduling its next poll fails" do
    tool = Class.new(RubyLLM::Tool) do
      description "Defer until the next worker"
      def initialize(**); end
      def execute = RubyLLM::Task.new(status: :working, poll_interval: 1)
      def resume(*) = "Work complete"
    end
    stub_const("DeferredQueueTool", tool)
    allow_any_instance_of(ToolsetService).to receive(:tool_classes).and_return([DeferredQueueTool])
    stub_replies tool_call(:deferred_queue), "Finished"
    allow(described_class).to receive(:set).and_return(described_class)
    allow(described_class).to receive(:perform_later).and_raise(ActiveJob::EnqueueError, "queue offline")
    run = new_run

    described_class.perform_now(run.id)

    expect(run.reload).to be_status_awaiting_tasks
    expect(run.resume_at).to be_present
    expect(Chat.find(chat.id).pending_tasks.size).to eq(1)
    run.update!(resume_at: 1.second.ago)
    allow(described_class).to receive(:perform_later)
    expect(run.recover!).to be true
    described_class.perform_now(run.id)
    expect(run.reload).to be_status_completed
    expect(chat.messages.where(role: :tool).sole.content).to eq("Work complete")
    expect(chat.messages.where(role: :user).count).to eq(1)
  end

  it "does not wake an input-required task on a duplicate delivery" do
    tool = Class.new(RubyLLM::Tool) do
      description "Wait for external confirmation"
      def initialize(**); end
      def execute = RubyLLM::Task.new(status: :input_required, data: { "reference" => "abc" })
      def resume(*) = raise("A duplicate delivery must not resume this task")
    end
    stub_const("AwaitExternalTool", tool)
    allow_any_instance_of(ToolsetService).to receive(:tool_classes).and_return([AwaitExternalTool])
    stub_replies tool_call(:await_external)
    run = new_run
    described_class.perform_now(run.id)
    described_class.perform_now(run.id)
    expect(run.reload).to be_status_awaiting_tasks
    expect(chat.messages.where(role: :user).count).to eq(1)
  end
end
