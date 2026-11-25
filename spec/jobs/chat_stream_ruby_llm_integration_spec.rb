# frozen_string_literal: true

require "rails_helper"
require "ruby_llm/test_helper"

RSpec.describe "Chat streaming with RubyLLM 2.2", type: :job do
  include RubyLLM::TestHelper

  let(:chat) { chats(:alice_personal_chat) }
  let(:member) { members(:alice_personal_member) }

  before do
    chat.chat_runs.active.delete_all
    chat.messages.destroy_all
    allow(Turbo::StreamsChannel).to receive(:broadcast_append_to)
    allow(Turbo::StreamsChannel).to receive(:broadcast_replace_to)
    allow(Turbo::StreamsChannel).to receive(:broadcast_action_to)
    allow(Turbo::StreamsChannel).to receive(:broadcast_stream_to)
    allow_any_instance_of(ToolsetService).to receive(:tool_classes).and_return([ Examples::RenameChatTool ])
  end

  def start_run(content: "Rename this chat", automated: false)
    message = chat.messages.create!(
      role: :user, content: content, user_submitted: !automated,
      member: automated ? nil : member, user: automated ? nil : member.user
    )
    run = chat.chat_runs.create!(initiated_by_member: member, input_message: message, status: :pending)
    ChatStreamJob.perform_now(run.id)
    run.reload
  end

  def resume_run(run)
    ChatStreamJob.perform_now(run.id)
    run.reload
  end

  it "stops a repeated tool loop, preserving its results and usage without retrying" do
    executions = []
    tool = Class.new(RubyLLM::Tool) do
      description "Perform a small unit of work"
      def initialize(**); end
      define_method(:execute) { executions << :performed; "Done" }
    end
    stub_const("BoundedWorkTool", tool)
    allow_any_instance_of(ToolsetService).to receive(:tool_classes).and_return([ BoundedWorkTool ])
    allow(Rails.configuration.x.llm).to receive(:tool_options).and_return(rounds: 2, calls: 2)
    stub_replies tool_call(:bounded_work), tool_call(:bounded_work), "This must not be requested", cost: 0.01

    run = start_run(content: "Keep working")

    expect(run).to be_status_failed
    expect(executions).to eq([ :performed, :performed ])
    expect(chat.messages.where(role: :tool).pluck(:content)).to eq([ "Done", "Done" ])
    expect(chat.messages.where(role: :assistant).last.content).to include("tool limit")
    expect(run.llm_attempts).to eq(2)
    expect(run.total_cost).to eq(BigDecimal("0.02"))
  end

  it "applies the same loop boundary to reusable native agents" do
    tool = Class.new(RubyLLM::Tool) do
      description "Perform a unit of work"
      def execute = "Done"
    end
    stub_const("NativeWorkTool", tool)
    agent_class = Class.new(ApplicationAgent) { tools NativeWorkTool }
    stub_const("BoundedNativeAgent", agent_class)
    allow(Rails.configuration.x.llm).to receive(:tool_options).and_return(rounds: 1, calls: 2)
    stub_replies tool_call(:native_work), "This must not be requested"

    expect { BoundedNativeAgent.new(chat: chat).ask("Keep working") }
      .to raise_error(RubyLLM::ToolRoundLimitError)
    expect(chat.messages.where(role: :tool).sole.content).to eq("Done")
  end

  it "caps one response's tool calls before executing excess actions" do
    executions = []
    tool = Class.new(RubyLLM::Tool) do
      description "Perform a small unit of work"
      def initialize(**); end
      define_method(:execute) { executions << :performed; "Done" }
    end
    stub_const("CappedWorkTool", tool)
    allow_any_instance_of(ToolsetService).to receive(:tool_classes).and_return([ CappedWorkTool ])
    allow(Rails.configuration.x.llm).to receive(:tool_options).and_return(rounds: 2, calls: 2)
    calls = Array.new(3) { tool_call(:capped_work) }
    stub_replies calls.first, "The allowed work is done."
    allow_any_instance_of(RubyLLM::Providers::Anthropic).to receive(:complete).and_wrap_original do |original, *args, **kwargs, &block|
      reply = original.call(*args, **kwargs, &block)
      reply.tool_call? ? reply.with_tool_calls(calls.index_by(&:id)) : reply
    end

    run = start_run(content: "Do three units of work")

    expect(run).to be_status_completed
    expect(executions).to eq([ :performed, :performed ])
    results = chat.messages.where(role: :tool).order(:id).to_a
    expect(results.first(2).map(&:content)).to eq([ "Done", "Done" ])
    expect(results.last.to_llm.tool_error_message).to be_present
    expect(run.pending_questions).to be_empty
    expect(chat.messages.where(role: :assistant).last.content).to eq("The allowed work is done.")
  end

  it "persists an approval, resumes it in a fresh job, and accounts for both provider attempts" do
    stub_replies tool_call(Examples::RenameChatTool.tool_name, title: "Approved title"), "Renamed.", cost: 0.01

    run = start_run
    expect(run).to be_status_awaiting_approval
    question = run.pending_questions.sole
    expect(question).to be_approval

    run.decide_tool_call!(question.id, decision: "approved", member: member)
    resume_run(run)

    expect(run).to be_status_completed
    expect(chat.reload.name).to eq("Approved title")
    expect(run.llm_attempts).to eq(2)
    expect(run.total_cost).to eq(BigDecimal("0.02"))
    expect(run.owned_llm_usages.count).to eq(2)
    expect(chat.messages.where(role: :assistant).last.content).to eq("Renamed.")
  end

  it "declines an approval without executing its tool" do
    original_name = chat.name
    stub_replies tool_call(Examples::RenameChatTool.tool_name, title: "Must not change"), "I kept the title."

    run = start_run
    run.decide_tool_call!(run.pending_questions.sole.id, decision: "denied", member: member)
    resume_run(run)

    expect(run).to be_status_completed
    expect(chat.reload.name).to eq(original_name)
    expect(chat.messages.where(role: :tool).sole.content).to include("denied")
  end

  it "carries a tool question through durable answer and execution" do
    tool = Class.new(RubyLLM::Tool) do
      description "Choose the format for a report"

      def initialize(**); end

      def execute
        format = ask("Which format?", choices: %w[summary detailed])
        { format: format }
      end
    end
    stub_const("ReportFormatTool", tool)
    allow_any_instance_of(ToolsetService).to receive(:tool_classes).and_return([ ReportFormatTool ])
    stub_replies tool_call(:report_format), "I will use a summary."

    run = start_run(content: "Prepare a report")
    expect(run).to be_status_awaiting_approval
    question = run.pending_questions.sole
    expect(question.message).to eq("Which format?")
    run.answer_question!(question.id, member: member, answer: "summary")
    resume_run(run)

    expect(run).to be_status_completed
    expect(chat.messages.where(role: :tool).sole.content).to include("summary")
  end

  it "uses the initiating member for scheduled messages without a human sender" do
    stub_replies tool_call(Examples::RenameChatTool.tool_name, title: "Scheduled title"), "Renamed."

    run = start_run(automated: true)

    expect(run).to be_status_awaiting_approval
    expect(run.approval_tool_calls.sole.metadata["requester_member_id"]).to eq(member.id)
  end

  it "leaves a run alone while another process holds its chat claim" do
    run = chat.chat_runs.create!(initiated_by_member: member, status: :running)
    chat.update!(claim_token: "another-process", claimed_until: 1.minute.from_now)
    expect_any_instance_of(Chat).not_to receive(:complete)
    expect(ChatStreamJob).not_to receive(:set)

    ChatStreamJob.perform_now(run.id)

    expect(run.reload).to be_status_running
    expect(chat.reload.claim_token).to eq("another-process")
  end

  it "preserves an approved pending call when resuming an expired native claim" do
    stub_replies tool_call(Examples::RenameChatTool.tool_name, title: "Recovered title"), "Recovered."
    run = start_run
    run.decide_tool_call!(run.pending_questions.sole.id, decision: "approved", member: member)
    chat.reload.update!(claim_token: "crashed-process", claimed_until: 1.minute.ago)

    ChatStreamJob.perform_now(run.id)

    expect(run.reload).to be_status_completed
    expect(chat.reload.name).to eq("Recovered title")
    expect(chat.messages.where(role: :tool).count).to eq(1)
  end

  it "recovers a pending delivery after a previous claim expires without a retry chain" do
    chat.update!(claim_token: "previous-run", claimed_until: 1.minute.from_now)
    message = chat.messages.create!(role: :user, content: "One more thing", member: member, user: member.user)
    run = chat.chat_runs.create!(initiated_by_member: member, input_message: message)
    allow(ChatStreamJob).to receive(:perform_later)
    stub_replies "Here is the follow-up."
    160.times { ChatStreamJob.perform_now(run.id) }
    expect(run.reload).to be_status_pending
    expect(ChatStreamJob).not_to have_received(:perform_later)
    expect(chat.messages.where(role: :assistant)).to be_empty
    chat.update!(claimed_until: 1.minute.ago)
    ResumeChatRunsJob.perform_now
    expect(ChatStreamJob).to have_received(:perform_later).with(run.id)
    ChatStreamJob.perform_now(run.id)
    expect(run.reload).to be_status_completed
    expect(run.llm_attempts).to eq(1)
  end

  it "never fails an active owner after repeated duplicate deliveries" do
    run = chat.chat_runs.create!(initiated_by_member: member, status: :running)
    chat.update!(claim_token: "same-run-owner", claimed_until: 30.minutes.from_now)
    expect_any_instance_of(Chat).not_to receive(:complete)
    expect(ChatStreamJob).not_to receive(:set)
    160.times { ChatStreamJob.perform_now(run.id) }
    expect(run.reload).to be_status_running
    expect(chat.reload.claim_token).to eq("same-run-owner")
    expect(chat.messages.where(role: :assistant)).to be_empty
  end

  it "does not recover cancelled work after a claim expires" do
    run = chat.chat_runs.create!(initiated_by_member: member, status: :cancelled)
    chat.update!(claim_token: "previous-run", claimed_until: 1.minute.ago)
    expect_any_instance_of(Chat).not_to receive(:complete)
    ChatStreamJob.perform_now(run.id)
    expect(run.reload).to be_status_cancelled
  end
end
