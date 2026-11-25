# frozen_string_literal: true
require "rails_helper"
require "ruby_llm/test_helper"

RSpec.describe "Durable chat execution", type: :job do
  include RubyLLM::TestHelper
  let(:chat) { chats(:alice_personal_chat) }
  let(:member) { members(:alice_personal_member) }

  before do
    chat.chat_runs.active.delete_all
    chat.messages.destroy_all
    allow(Turbo::StreamsChannel).to receive(:broadcast_action_to)
    allow(Turbo::StreamsChannel).to receive(:broadcast_replace_to)
    allow(Turbo::StreamsChannel).to receive(:broadcast_append_to)
    allow(ChatStreamJob).to receive(:perform_later)
  end

  def new_run
    message = chat.messages.create!(role: :user, content: "Process this document", member: member, user: member.user)
    chat.chat_runs.create!(input_message: message, initiated_by_member: member)
  end

  it "resumes a native task from persisted state without repeating execute or adding a user turn" do
    executed, resumed = [], []
    tool = Class.new(RubyLLM::Tool) do
      description "Start durable document processing"
      define_method(:initialize) { |**| }
      define_method(:execute) do
        executed << :started
        RubyLLM::Task.new(status: :working, poll_interval: 1, data: { "document" => "invoice" })
      end
      define_method(:resume) do |task, **|
        resumed << task.data.fetch("document")
        "Document processed"
      end
    end
    stub_const("DurableDocumentTool", tool)
    allow_any_instance_of(ToolsetService).to receive(:tool_classes).and_return([DurableDocumentTool])
    stub_replies tool_call(:durable_document), "The document is ready.", cost: 0.01
    run = new_run
    ChatStreamJob.perform_now(run.id)
    expect(run.reload).to be_status_awaiting_tasks
    expect(Chat.find(chat.id).pending_tasks.sole.data).to eq("document" => "invoice")
    expect(run.resume_at).to be_present

    ChatStreamJob.perform_now(run.id)
    ChatStreamJob.perform_now(run.id) # duplicate delivery after completion
    expect(run.reload).to be_status_completed
    expect(executed).to eq([:started])
    expect(resumed).to eq(["invoice"])
    expect(chat.messages.where(role: :user).count).to eq(1)
    expect(chat.messages.where(role: :tool).sole.content).to eq("Document processed")
    expect(run.owned_llm_usages.count).to eq(2)
  end

  it "recovers lost dispatch from its persisted input and original actor" do
    run = new_run
    ResumeChatRunsJob.perform_now
    expect(ChatStreamJob).to have_received(:perform_later).with(run.id)
    expect(run.reload.input_message.content).to eq("Process this document")
    expect(run.execution_member!).to eq(member)
  end

  it "leaves live native claims and human approval waits alone" do
    run = new_run
    chat.update!(claim_token: "live-worker", claimed_until: 1.minute.from_now)
    ResumeChatRunsJob.perform_now
    expect(ChatStreamJob).not_to have_received(:perform_later)
    chat.update!(claim_token: nil, claimed_until: nil)
    run.update!(status: :awaiting_approval)
    ResumeChatRunsJob.perform_now
    expect(ChatStreamJob).not_to have_received(:perform_later)
  end

  it "recovers an expired native claim" do
    run = new_run
    chat.update!(claim_token: "dead-worker", claimed_until: 1.minute.ago)
    expect(Chat.interrupted).to include(chat)
    ResumeChatRunsJob.perform_now
    expect(ChatStreamJob).to have_received(:perform_later).with(run.id)
  end

  it "does not let a legacy payload replace the stored actor or chat" do
    run = new_run
    expect { ChatStreamJob.perform_now(chats(:team_chat).id, nil, run.id) }.to raise_error(ArgumentError)
    expect(run.reload.initiated_by_member).to eq(member)
  end

  it "fails closed after membership revocation before any provider work" do
    run = new_run
    chat.chat_members.where(member: member).delete_all
    expect_any_instance_of(Chat).not_to receive(:complete)
    expect { ChatStreamJob.perform_now(run.id) }.to raise_error(Pundit::NotAuthorizedError)
    expect(run.reload).to be_status_failed
  end

  it "does not resurrect a run cancelled during setup" do
    run = new_run
    allow(ChatPurpose).to receive(:bind).and_wrap_original do |original, **args|
      result = original.call(**args)
      ChatRun.find(run.id).cancel!
      result
    end
    expect_any_instance_of(Chat).not_to receive(:complete)
    ChatStreamJob.perform_now(run.id)
    expect(run.reload).to be_status_cancelled
  end

  it "keeps input-required native tasks parked until an explicit application callback" do
    tool = Class.new(RubyLLM::Tool) do
      description "Wait for a signed document"
      def initialize(**); end
      def execute = RubyLLM::Task.new(status: :input_required, data: { "envelope" => "123" })
      def resume(task, **) = task
    end
    stub_const("SignatureWaitTool", tool)
    allow_any_instance_of(ToolsetService).to receive(:tool_classes).and_return([SignatureWaitTool])
    stub_replies tool_call(:signature_wait)
    run = new_run
    ChatStreamJob.perform_now(run.id)
    expect(run.reload).to be_status_awaiting_tasks
    expect(run.resume_at).to be_nil
    ResumeChatRunsJob.perform_now
    expect(ChatStreamJob).not_to have_received(:perform_later)
    expect(run.resume_tasks!(explicit: true)).to be true
    expect(ChatStreamJob).to have_received(:perform_later).with(run.id)
  end

  it "preserves completed tool effects when cancelled" do
    stub_replies tool_call(Examples::RenameChatTool.tool_name, title: "Kept title"), "Done."
    allow_any_instance_of(ToolsetService).to receive(:tool_classes).and_return([Examples::RenameChatTool])
    run = new_run
    ChatStreamJob.perform_now(run.id)
    run.answer_question!(run.pending_questions.sole.id, member: member, decision: "approved")
    ChatStreamJob.perform_now(run.id)
    run.update!(status: :running)
    ids = chat.messages.pluck(:id)
    call_ids = RubyLLM::ActiveRecord::ToolCall.where(message_id: ids).pluck(:id)
    run.cancel!
    expect(chat.messages.pluck(:id)).to match_array(ids)
    expect(RubyLLM::ActiveRecord::ToolCall.where(id: call_ids).count).to eq(call_ids.size)
    expect(chat.reload.name).to eq("Kept title")
  end
end
