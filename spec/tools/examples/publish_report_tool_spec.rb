# frozen_string_literal: true

require "rails_helper"
require "ruby_llm/test_helper"

RSpec.describe Examples::PublishReportTool, type: :job do
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
    chat.chat_runs.active.delete_all
    chat.messages.destroy_all
    allow(Turbo::StreamsChannel).to receive(:broadcast_action_to)
    allow(Turbo::StreamsChannel).to receive(:broadcast_replace_to)
    allow(Turbo::StreamsChannel).to receive(:broadcast_append_to)
    allow(Turbo::StreamsChannel).to receive(:broadcast_stream_to)
    allow(ChatPurpose).to receive(:registry).and_return("report_publication" => Examples::ReportPublisherAgent)
    chat.update!(purpose: "report_publication")
    allow(Examples::PublishReportJob).to receive(:perform_later)
    allow(ChatStreamJob).to receive(:perform_later)
  end

  def prepare_report(publication_key: "monthly-summary:2026-11:revision-1", body: "Two reviewed invoices.")
    Examples::ReportPublication.create!(workspace: member.workspace, chat: chat, member: member,
      publication_key: publication_key, title: "Monthly summary", body: body)
  end

  def propose(report)
    input = chat.messages.create!(role: :user, content: "Publish prepared report #{report.id}", member: member, user: member.user)
    run = chat.chat_runs.create!(input_message: input, initiated_by_member: member)
    stub_replies tool_call(described_class.tool_name, report_id: report.id), "The report is published."
    ChatStreamJob.perform_now(run.id)
    expect(run.reload).to be_status_awaiting_approval
    run
  end

  def approve(run)
    run.answer_question!(run.pending_questions.sole.id, member: member, decision: "approved")
    ChatStreamJob.perform_now(run.id)
    run.reload
  end

  it "parks for approval, persists a native task, and resumes after a separate worker delivery" do
    report = prepare_report
    run = propose(report)
    expect(report.reload).to be_status_draft
    expect(Examples::PublishReportJob).not_to have_received(:perform_later)

    approve(run)
    expect(run).to be_status_awaiting_tasks
    expect(report.reload).to be_status_queued
    expect(Chat.find(chat.id).pending_tasks.sole.data).to eq("report_id" => report.id)
    expect(Examples::PublishReportJob).to have_received(:perform_later).with(report.id).once

    Examples::PublishReportJob.perform_now(report.id)
    published_at = report.reload.published_at
    Examples::PublishReportJob.perform_now(report.id)
    expect(report.reload.published_at).to eq(published_at)
    ChatStreamJob.perform_now(run.id)

    expect(run.reload).to be_status_completed
    expect(chat.messages.where(role: :user).count).to eq(1)
    expect(chat.messages.where(role: :tool).sole.content).to include('"status":"published"')
  end

  it "reuses the same business publication when a new call and run propose it again" do
    report = prepare_report
    first = propose(report)
    approve(first)
    Examples::PublishReportJob.perform_now(report.id)
    ChatStreamJob.perform_now(first.id)
    published_at = report.reload.published_at
    second = propose(report)
    approve(second)

    expect(second).to be_status_completed
    expect(report.reload.published_at).to eq(published_at)
    expect(report.chat_run_id).to eq(first.id)
    expect(Examples::ReportPublication.where(workspace: member.workspace, publication_key: report.publication_key).count).to eq(1)
    expect(Examples::PublishReportJob).to have_received(:perform_later).once
  end

  it "redelivers a lost publication job from the persisted native task" do
    report = prepare_report
    run = propose(report)
    approve(run)
    ChatStreamJob.perform_now(run.id)

    expect(run.reload).to be_status_awaiting_tasks
    expect(Examples::PublishReportJob).to have_received(:perform_later).with(report.id).twice
    expect(chat.messages.where(role: :user).count).to eq(1)
    Examples::PublishReportJob.perform_now(report.id)
    ChatStreamJob.perform_now(run.id)
    expect(run.reload).to be_status_completed
  end

  it "keeps a queue enqueue failure resumable without losing the native task" do
    allow(Examples::PublishReportJob).to receive(:perform_later).and_raise(SolidQueue::Job::EnqueueError, "offline")
    report = prepare_report
    run = propose(report)
    approve(run)

    expect(run).to be_status_awaiting_tasks
    expect(report.reload).to be_status_queued
    expect(Chat.find(chat.id).pending_tasks.sole.data).to eq("report_id" => report.id)
  end

  it "recovers committed publication intent after exit before enqueue and native task persistence" do
    report = prepare_report
    run = propose(report)
    allow_any_instance_of(Examples::ReportPublication).to receive(:dispatch_if_pending!).and_raise(Interrupt, "simulated worker exit")
    expect { approve(run) }.to raise_error(Interrupt)

    expect(report.reload).to be_status_queued
    expect(Chat.find(chat.id).pending_tasks).to be_empty
    expect(Examples::PublishReportJob).not_to have_received(:perform_later)
    allow_any_instance_of(Examples::ReportPublication).to receive(:dispatch_if_pending!).and_call_original

    Examples::ResumeReportPublicationsJob.perform_now
    expect(Examples::PublishReportJob).to have_received(:perform_later).with(report.id).once
    Examples::PublishReportJob.perform_now(report.id)
    expect(report.reload).to be_status_published
    published_at = report.published_at
    Examples::ResumeReportPublicationsJob.perform_now
    Examples::PublishReportJob.perform_now(report.id)
    expect(report.reload.published_at).to eq(published_at)
  end

  it "reconciles queued intent from a terminal run without needing a publication worker" do
    report = prepare_report
    run = propose(report)
    approve(run)
    run.update!(status: :failed)

    Examples::ResumeReportPublicationsJob.perform_now
    expect(report.reload).to be_status_cancelled
    expect(report.published_at).to be_nil
    expect(Examples::PublishReportJob).to have_received(:perform_later).once
  end

  it "does not publish when the run was cancelled before the application worker executes" do
    report = prepare_report
    run = propose(report)
    approve(run)
    run.cancel!
    Examples::PublishReportJob.perform_now(report.id)

    expect(report.reload).to be_status_cancelled
    expect(report.published_at).to be_nil
  end

  it "does not mutate a prepared draft when a worker is invoked before approval" do
    report = prepare_report
    Examples::PublishReportJob.perform_now(report.id)
    expect(report.reload).to be_status_draft
    expect(report.published_at).to be_nil
  end

  it "reconstructs a native task cancellation handler for the pending business operation" do
    report = prepare_report
    run = propose(report)
    approve(run)
    bound = ChatPurpose.bind(chat: Chat.find(chat.id), run: run)
    task = bound.pending_tasks.sole
    expect(task).to be_a(Examples::ReportPublicationTask)
    task.cancel
    Examples::PublishReportJob.perform_now(report.id)

    expect(report.reload).to be_status_cancelled
    expect(report.published_at).to be_nil
  end

  it "reauthorizes the original actor before publication and fails closed after revocation" do
    report = prepare_report
    run = propose(report)
    approve(run)
    chat.chat_members.where(member: member).delete_all
    Examples::PublishReportJob.perform_now(report.id)

    expect(report.reload).to be_status_cancelled
    expect(report.published_at).to be_nil
  end

  it "rejects a prepared record outside the run's chat and workspace" do
    report = prepare_report
    foreign_chat = chats(:team_chat)
    foreign_run = foreign_chat.chat_runs.create!(initiated_by_member: members(:alice_team_member))
    tool = described_class.new(chat: foreign_chat, run: foreign_run)

    expect { tool.execute(report_id: report.id) }.to raise_error(ActiveRecord::RecordNotFound)
    expect(report.reload).to be_status_draft
  end

  it "keeps the prepared content immutable while approval is pending and after publication" do
    report = prepare_report
    propose(report)
    expect { report.update!(body: "Changed after the proposal") }.to raise_error(ActiveRecord::RecordInvalid)
    expect(report.reload.body).to eq("Two reviewed invoices.")
  end

  it "enforces the business identity in the database, independently of model validations" do
    report = prepare_report
    duplicate = report.dup
    expect { duplicate.save!(validate: false) }.to raise_error(ActiveRecord::RecordNotUnique)
  end

  it "runs deterministic native evaluations on ordinary and malicious report text without provider calls" do
    pipeline = lambda do |input|
      chat.messages.destroy_all
      report = prepare_report(publication_key: input.fetch("publication_key"), body: input.fetch("body"))
      run = propose(report)
      approve(run)
      Examples::PublishReportJob.perform_now(report.id)
      ChatStreamJob.perform_now(run.id)
      {
        "status" => report.reload.status,
        "original_input_preserved" => report.body == input.fetch("body"),
        "one_business_effect" => Examples::ReportPublication.where(workspace: member.workspace, publication_key: report.publication_key).count == 1
      }
    end
    evaluation = Class.new(RubyLLM::Evaluation) do
      evaluator false
      dataset Rails.root.join("spec/fixtures/files/native_recipe/report_cases.json")
      define_method(:perform) { |input| pipeline.call(input) }
      def assertions
        assert_equal expected_output, output
      end
    end
    stub_const("ReportPublicationContractEvaluation", evaluation)

    report = ReportPublicationContractEvaluation.run
    expect(report).to be_passed, report.to_json
    expect(report.trials.size).to eq(2)
  end
end
