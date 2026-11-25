# frozen_string_literal: true

require "rails_helper"

RSpec.describe AgentDeliveryJob, type: :job do
  include ActiveSupport::Testing::TimeHelpers

  let(:member) { members(:alice_personal_member) }
  let(:chat) { Chat.create!(member: member, name: "Inbox") }
  let(:agent) { Agent.create!(workspace: member.workspace, member: member, chat: chat, name: "Inbox", identifier: "inbox") }
  let(:delivery) { AgentDelivery.accept!(agent: agent, trigger: "webhook", payload: '{"n":1}', event_type: "created", idempotency_key: "event-1") }

  before { allow(ChatStreamJob).to receive(:perform_later) }

  it "atomically creates one input and run and preserves the receipt actor" do
    delivery
    expect { described_class.perform_now(delivery.id) }.to change(Message, :count).by(1).and change(ChatRun, :count).by(1)
    expect(delivery.reload).to be_status_dispatched
    expect(delivery.chat_run).to have_attributes(initiated_by_member: member, input_message: delivery.input_message, trigger: "webhook")
    expect(delivery.input_message.content).to include("Webhook received: created", '{"n":1}')
    expect(ChatStreamJob).to have_received(:perform_later).with(delivery.chat_run_id)
    expect { described_class.perform_now(delivery.id) }.not_to change(ChatRun, :count)
    expect(chat.messages.count).to eq(1)
  end

  it "waits durably behind a pending approval without appending another input" do
    current = chat.chat_runs.create!(status: :awaiting_approval, initiated_by_member: member)
    described_class.perform_now(delivery.id)
    expect(delivery.reload).to be_status_pending
    expect(delivery.input_message).to be_nil
    expect(chat.messages.count).to eq(0)

    current.update!(status: :completed)
    travel 6.seconds do
      allow(AgentDeliveryJob).to receive(:perform_later)
      ResumeAgentDeliveriesJob.perform_now
      expect(AgentDeliveryJob).to have_received(:perform_later).with(delivery.id)
      described_class.perform_now(delivery.id)
    end
    expect(delivery.reload).to be_status_dispatched
    expect(chat.messages.count).to eq(1)
    expect(chat.chat_runs.count).to eq(2)
  end

  it "retains a created run for ChatRun recovery when its queue enqueue fails" do
    allow(ChatStreamJob).to receive(:perform_later).and_raise(ActiveJob::EnqueueError, "queue offline")
    expect { described_class.new.perform(delivery.id) }.not_to raise_error
    expect(delivery.reload).to be_status_dispatched
    expect(delivery.chat_run).to be_status_pending
    allow(ChatStreamJob).to receive(:perform_later)
    delivery.chat_run.recover!
    expect(ChatStreamJob).to have_received(:perform_later).with(delivery.chat_run_id).twice
    expect(chat.chat_runs.count).to eq(1)
  end

  it "waits for a native claim even when no application run exists" do
    delivery
    chat.update_columns(claim_token: "external-worker", claimed_until: 1.minute.from_now)
    described_class.perform_now(delivery.id)
    expect(delivery.reload).to be_status_pending
    expect(chat.messages.count).to eq(0)
    travel 2.minutes do
      described_class.perform_now(delivery.id)
    end
    expect(delivery.reload).to be_status_dispatched
  end

  it "rolls the input back if run creation fails" do
    delivery
    allow_any_instance_of(ChatRun).to receive(:save!).and_raise(ActiveRecord::RecordInvalid.new(ChatRun.new))
    expect { described_class.new.perform(delivery.id) }.to raise_error(ActiveRecord::RecordInvalid)
    expect(delivery.reload).to be_status_pending
    expect(chat.messages.count).to eq(0)
    expect(chat.chat_runs.count).to eq(0)
  end

  it "does not adopt a newly assigned agent member" do
    delivery
    other = members(:bob_personal_member)
    agent.update!(member: other)
    described_class.perform_now(delivery.id)
    expect(delivery.reload.chat_run.initiated_by_member).to eq(member)
  end

  it "rejects accepted work after the original actor loses chat access" do
    delivery
    chat.chat_members.where(member: member).delete_all
    described_class.perform_now(delivery.id)
    expect(delivery.reload).to have_attributes(status: "rejected", rejection_reason: "access_revoked", chat_run_id: nil)
    expect(chat.messages.count).to eq(0)
  end

  it "rejects work for an agent disabled after acceptance" do
    delivery
    agent.update!(active: false)
    described_class.perform_now(delivery.id)
    expect(delivery.reload).to have_attributes(status: "rejected", rejection_reason: "agent_inactive")
    expect(chat.chat_runs.count).to eq(0)
  end

  it "keeps delivery pending when an inbox recovery enqueue fails" do
    delivery
    allow(AgentDeliveryJob).to receive(:perform_later).and_raise(ActiveJob::EnqueueError)
    expect { ResumeAgentDeliveriesJob.perform_now }.not_to raise_error
    expect(delivery.reload).to be_status_pending
  end

  it "handles a deleted receipt" do
    expect { described_class.perform_now(-1) }.not_to raise_error
  end
end
