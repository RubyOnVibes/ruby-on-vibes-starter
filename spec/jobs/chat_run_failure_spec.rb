# frozen_string_literal: true

require "rails_helper"
require "ruby_llm/test_helper"

RSpec.describe "Terminal native run settlement", type: :job do
  include RubyLLM::TestHelper

  let(:chat) { chats(:alice_personal_chat) }
  let(:member) { members(:alice_personal_member) }

  around do |example|
    adapter = ActiveJob::Base.queue_adapter
    ActiveJob::Base.queue_adapter = :test
    example.run
  ensure
    ActiveJob::Base.queue_adapter = adapter
  end

  before do
    chat.chat_runs.delete_all
    chat.messages.destroy_all
    %i[broadcast_action_to broadcast_replace_to broadcast_append_to broadcast_stream_to].each do |method|
      allow(Turbo::StreamsChannel).to receive(method)
    end

    tool = Class.new(RubyLLM::Tool) do
      description "A provider-free failure settlement fixture"
      parameters do
        string :mode, required: true
      end
      def initialize(**); end
      def execute(mode:)
        return "Keep this completed result" if mode == "immediate"
        RubyLLM::Task.new(status: :working, data: { "reference" => "prepared-record" })
      end
      def resume(*) = raise("A failed run must never resume its old operation")
    end
    stub_const("FailureSettlementTool", tool)
    allow_any_instance_of(ToolsetService).to receive(:tool_classes).and_return([ FailureSettlementTool ])
  end

  def park_task
    input = chat.messages.create!(role: :user, content: "Prepare work", member: member, user: member.user)
    run = chat.chat_runs.create!(input_message: input, initiated_by_member: member)
    stub_replies tool_call(:failure_settlement, mode: "immediate"),
      tool_call(:failure_settlement, mode: "deferred")
    ChatStreamJob.perform_now(run.id)
    expect(run.reload).to be_status_awaiting_tasks
    expect(Chat.find(chat.id).pending_tasks.size).to eq(1)
    run
  end

  def expect_closed_native_history
    llm = Chat.find(chat.id).to_llm
    requested = llm.messages.flat_map { |message| message.tool_calls.keys }
    answered = llm.messages.filter_map(&:tool_call_id)
    expect(requested - answered).to be_empty
    expect(llm.pending_tasks).to be_empty
    expect(chat.messages.where(role: :tool).pluck(:content)).to include("Keep this completed result")
  end

  it "closes persisted tasks when the actor is revoked before the next native completion" do
    run = park_task
    chat.chat_members.where(member: member).delete_all

    expect { ChatStreamJob.perform_now(run.id) }.to raise_error(Pundit::NotAuthorizedError)

    expect(run.reload).to be_status_failed
    expect_closed_native_history
  end

  it "keeps failed cancellation recoverable without masking the original failure" do
    run = park_task
    chat.chat_members.where(member: member).delete_all
    allow_any_instance_of(Chat).to receive(:run_tools).and_raise(ArgumentError, "Secondary cancellation failure")

    expect { ChatStreamJob.perform_now(run.id) }.to raise_error(Pundit::NotAuthorizedError)

    expect(run.reload).to be_active
    expect(chat.reload.cancelled?).to be true
    expect(Chat.find(chat.id).pending_tasks.size).to eq(1)
    expect(chat.messages.where(skip_llm_context: true)).to be_empty

    allow_any_instance_of(Chat).to receive(:run_tools).and_call_original
    expect { ChatStreamJob.perform_now(run.id) }.to raise_error(Pundit::NotAuthorizedError)

    expect(run.reload).to be_status_failed
    expect(chat.messages.where(skip_llm_context: true).sole).to be_skip_llm_context
    expect_closed_native_history
  end

  it "settles a task through public cancellation and run_tools without calling the provider" do
    park_task
    fresh = Chat.find(chat.id)
    fresh.cancel

    expect { fresh.run_tools }.to raise_error(RubyLLM::CancelledError)

    expect_closed_native_history
  end

  it "settles a cancelled parked turn before a new user message can hide its task" do
    run = park_task
    run.cancel!
    input = chat.messages.create!(role: :user, content: "A new request", member: member, user: member.user)
    next_run = chat.chat_runs.create!(input_message: input, initiated_by_member: member)
    stub_replies "Answer to the new request"

    ChatStreamJob.perform_now(next_run.id)

    expect(next_run.reload).to be_status_completed
    expect_closed_native_history
    expect(chat.messages.where(role: :assistant).last.content).to eq("Answer to the new request")
  end

  it "requests cancellation without executing tools while another worker holds the native claim" do
    run = park_task
    chat.update_columns(claim_token: SecureRandom.uuid, claimed_until: 1.minute.from_now)

    run.cancel!

    expect(run.reload).to be_status_cancelled
    expect(chat.reload.cancelled?).to be true
    expect(Chat.find(chat.id).pending_tasks.size).to eq(1)
  end

  it "settles an approval without authorizing or executing the tool" do
    tool = Class.new(RubyLLM::Tool) do
      description "An approval which must never execute"
      requires_approval
      def initialize(**); end
      def execute = raise("Cancellation must not grant approval")
    end
    stub_const("NeverApprovedFixtureTool", tool)
    allow_any_instance_of(ToolsetService).to receive(:tool_classes).and_return([ NeverApprovedFixtureTool ])
    input = chat.messages.create!(role: :user, content: "Request approval", member: member, user: member.user)
    run = chat.chat_runs.create!(input_message: input, initiated_by_member: member)
    stub_replies tool_call(:never_approved_fixture)
    ChatStreamJob.perform_now(run.id)
    expect(run.reload).to be_status_awaiting_approval
    fresh = Chat.find(chat.id)
    fresh.cancel

    expect { fresh.run_tools }.to raise_error(RubyLLM::CancelledError)

    call = chat.messages.where(role: :assistant).sole.ruby_llm_tool_calls.sole
    expect(call.reload.result).to be_cancelled
    expect(call.approval).not_to eq("approved")
  end
end
