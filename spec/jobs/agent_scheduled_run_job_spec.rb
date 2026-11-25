# frozen_string_literal: true

require "rails_helper"

RSpec.describe AgentScheduledRunJob, type: :job do
  let(:member) { members(:alice_personal_member) }
  let(:agent) do
    Agent.create!(workspace: member.workspace, member: member,
      chat: Chat.create!(member: member, name: "Scheduled Agent Chat"),
      name: "Scheduled Agent", identifier: "scheduled_agent", schedule: "0 9 * * 1-5")
  end

  before do
    allow(AgentDeliveryJob).to receive(:perform_later)
    allow(ChatStreamJob).to receive(:perform_later)
  end

  it "uses the common inbox and preserves a scheduled trigger" do
    described_class.perform_now(agent.id, slot: "2026-11-26T09:00Z")
    delivery = AgentDelivery.last
    expect(delivery).to have_attributes(trigger: "schedule", initiated_by_member: member, status: "pending")
    expect(agent.chat.messages.count).to eq(0)
    AgentDeliveryJob.perform_now(delivery.id)
    expect(delivery.reload.chat_run.trigger).to eq("schedule")
    expect(delivery.input_message.content).to include("Scheduled run:")
  end

  it "deduplicates the same occurrence even after its run completes" do
    described_class.perform_now(agent.id, slot: "morning-2026-11-26")
    delivery = AgentDelivery.last
    AgentDeliveryJob.perform_now(delivery.id)
    delivery.reload.chat_run.update!(status: :completed)
    expect { described_class.perform_now(agent.id, slot: "morning-2026-11-26") }.not_to change(AgentDelivery, :count)
    expect(agent.chat.chat_runs.count).to eq(1)
  end

  it "deduplicates redelivery of the same queue job without a caller-supplied slot" do
    job = described_class.new
    job.perform(agent.id)
    expect { job.perform(agent.id) }.not_to change(AgentDelivery, :count)
  end

  it "preserves a new occurrence while its chat is busy" do
    agent.chat.chat_runs.create!(status: :running, initiated_by_member: member)
    described_class.perform_now(agent.id, slot: "afternoon-2026-11-26")
    delivery = AgentDelivery.last
    AgentDeliveryJob.perform_now(delivery.id)
    expect(delivery.reload).to be_status_pending
    expect(delivery.chat_run).to be_nil
    expect(agent.chat.messages.count).to eq(0)
  end

  it "skips inactive and missing agents" do
    agent.update!(active: false)
    expect { described_class.perform_now(agent.id) }.not_to change(AgentDelivery, :count)
    expect { described_class.perform_now(-1) }.not_to raise_error
  end
end
