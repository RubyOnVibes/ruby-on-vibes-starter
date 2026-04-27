# frozen_string_literal: true

require 'rails_helper'

RSpec.describe AgentScheduledRunJob, type: :job do
  let(:workspace) { workspaces(:alice_personal) }
  let(:member) { members(:alice_personal_member) }

  let(:agent) do
    chat = Chat.create!(member: member, name: "Scheduled Agent Chat")
    Agent.create!(
      workspace: workspace,
      member: member,
      chat: chat,
      name: "Scheduled Agent",
      identifier: "scheduled_agent",
      schedule: "0 9 * * 1-5",
      instructions: "You are a scheduled agent."
    )
  end

  before do
    allow(ChatStreamJob).to receive(:perform_later)
  end

  it 'creates a trigger message in the agent chat' do
    expect {
      described_class.new.perform(agent.id)
    }.to change { agent.chat.messages.count }.by(1)

    msg = agent.chat.messages.last
    expect(msg.role).to eq("user")
    expect(msg.content).to include("Scheduled run:")
    expect(msg.user_submitted).to be false
  end

  it 'creates an AgentTask with trigger: schedule' do
    expect {
      described_class.new.perform(agent.id)
    }.to change { AgentTask.count }.by(1)

    task = AgentTask.last
    expect(task.chat).to eq(agent.chat)
    expect(task.workspace).to eq(workspace)
    expect(task.member).to eq(member)
    expect(task.kind).to eq("scheduled_run")
    expect(task.trigger).to eq("schedule")
  end

  it 'enqueues a ChatStreamJob' do
    described_class.new.perform(agent.id)

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
      described_class.new.perform(agent.id)
    }.not_to change { agent.chat.messages.count }
  end

  it 'handles missing agent gracefully' do
    expect {
      described_class.new.perform(-1)
    }.not_to raise_error
  end
end
