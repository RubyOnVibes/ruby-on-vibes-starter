# frozen_string_literal: true

require 'rails_helper'

RSpec.describe "Chats#clear", type: :request do
  let(:alice) { users(:alice) }
  let(:workspace) { workspaces(:alice_personal) }
  let(:member) { members(:alice_personal_member) }
  let(:chat) { chats(:alice_personal_chat) }

  before do
    sign_in alice
    patch start_session_workspace_path(workspace)
  end

  describe "POST /chats/:id/clear" do
    it 'deletes all messages from the chat' do
      chat.messages.create!(role: "user", content: "Hello", user_submitted: true, user: alice, member: member)
      chat.messages.create!(role: "assistant", content: "Hi there", user: alice, member: member)

      expect {
        post clear_chat_path(chat)
      }.to change { chat.messages.count }.to(0)

      expect(response).to have_http_status(:no_content)
    end

    it 'deletes all chat runs' do
      ChatRun.create!(chat: chat, status: :completed)

      expect {
        post clear_chat_path(chat)
      }.to change { chat.chat_runs.count }.to(0)
    end

    it 'sets agent_tasks_dismissed_at to dismiss existing tasks' do
      expect(chat.agent_tasks_dismissed_at).to be_nil

      post clear_chat_path(chat)

      chat.reload
      expect(chat.agent_tasks_dismissed_at).to be_present
      expect(chat.agent_tasks_dismissed_at).to be_within(2.seconds).of(Time.current)
    end

    it 'does not cancel running agent tasks' do
      task = AgentTask.create!(
        chat: chat,
        workspace: workspace,
        member: member,
        kind: "test_task",
        status: :running
      )

      post clear_chat_path(chat)

      task.reload
      expect(task.status).to eq("running")
    end

    it 'deletes messages with tool calls and mentions' do
      # Create assistant message with a tool call
      assistant_msg = chat.messages.create!(role: "assistant", content: "Let me check that.", user: alice, member: member)
      tool_call = ToolCall.create!(message: assistant_msg, name: "echo_agent_task", tool_call_id: "call_123", arguments: "{}")
      tool_msg = chat.messages.create!(role: "tool", content: '{"result":"ok"}', tool_call_id: tool_call.id)

      # Create user message with a mention
      user_msg = chat.messages.create!(role: "user", content: "Check @agent", user_submitted: true, user: alice, member: member)
      Mention.create!(message: user_msg, mentionable: chat)

      expect {
        post clear_chat_path(chat)
      }.to change { chat.messages.count }.to(0)
       .and change { ToolCall.where(message_id: [assistant_msg.id, tool_msg.id]).count }.to(0)
       .and change { Mention.where(message_id: user_msg.id).count }.to(0)

      expect(response).to have_http_status(:no_content)
    end

    it 'requires authentication' do
      sign_out alice
      post clear_chat_path(chat)
      expect(response).to redirect_to(new_user_session_path)
    end
  end
end
