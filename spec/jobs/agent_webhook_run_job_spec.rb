# frozen_string_literal: true

require 'rails_helper'

RSpec.describe AgentWebhookRunJob, type: :job do
  let(:workspace) { workspaces(:alice_personal) }
  let(:member) { members(:alice_personal_member) }

  let(:agent) do
    chat = Chat.create!(member: member, name: "Webhook Agent Chat")
    Agent.create!(
      workspace: workspace,
      member: member,
      chat: chat,
      name: "Webhook Agent",
      identifier: "webhook_agent",
      instructions: "You handle webhooks."
    )
  end

  let(:task) do
    AgentTask.create!(
      chat: agent.chat,
      workspace: workspace,
      member: member,
      kind: "webhook_run",
      trigger: "webhook",
      metadata: { webhook_payload: { event: "push" } }
    )
  end

  before do
    allow(ChatStreamJob).to receive(:perform_later)
  end

  it 'starts the agent task' do
    described_class.new.perform(agent.id, task.id)

    task.reload
    expect(task.status).to eq("running")
    expect(task.started_at).to be_present
  end

  it 'creates a ChatRun' do
    expect {
      described_class.new.perform(agent.id, task.id)
    }.to change { agent.chat.chat_runs.count }.by(1)
  end

  it 'enqueues a ChatStreamJob with correct args' do
    described_class.new.perform(agent.id, task.id)

    expect(ChatStreamJob).to have_received(:perform_later).with(
      agent.chat.id,
      nil,
      anything,
      hash_including(sender_member_id: member.id, sender_user_id: member.user_id)
    )
  end

  it 'skips inactive agents' do
    agent.update!(active: false)

    expect {
      described_class.new.perform(agent.id, task.id)
    }.not_to change { agent.chat.chat_runs.count }

    task.reload
    expect(task.status).to eq("pending")
  end

  it 'skips terminal tasks' do
    task.update!(status: :completed, completed_at: Time.current)

    expect {
      described_class.new.perform(agent.id, task.id)
    }.not_to change { agent.chat.chat_runs.count }
  end

  it 'handles missing agent gracefully' do
    expect {
      described_class.new.perform(-1, task.id)
    }.not_to raise_error
  end

  it 'handles missing task gracefully' do
    expect {
      described_class.new.perform(agent.id, -1)
    }.not_to raise_error
  end
end
