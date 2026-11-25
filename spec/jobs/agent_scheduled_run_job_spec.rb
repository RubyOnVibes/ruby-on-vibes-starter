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

  it 'uses the durable run itself for schedule tracking' do
    expect { described_class.new.perform(agent.id) }.not_to change(AgentTask, :count)
    run = agent.chat.chat_runs.last
    expect(run.trigger).to eq("schedule")
    expect(run.initiated_by_member).to eq(member)
    expect(run.input_message.content).to include("Scheduled run:")
    expect(ChatStreamJob).to have_received(:perform_later).with(run.id)
  end

  it 'does not create another turn while the first is active' do
    described_class.new.perform(agent.id)
    expect { described_class.new.perform(agent.id) }.not_to change(Message, :count)
    expect(agent.chat.chat_runs.count).to eq(1)
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
