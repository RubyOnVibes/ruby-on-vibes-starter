# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Chat, type: :model do
  describe 'associations' do
    it 'belongs to member' do
      expect(chats(:alice_personal_chat).member).to eq(members(:alice_personal_member))
    end

    it 'has members through chat_members' do
      expect(chats(:team_chat).members).to include(
        members(:alice_team_member),
        members(:bob_team_member)
      )
    end
    end
    
  describe '#owner? / #member_exists? / #admin?' do
    it 'owner has full access' do
      chat = chats(:team_chat)
      expect(chat.owner?(members(:alice_team_member))).to be true
      expect(chat.member_exists?(members(:alice_team_member))).to be true
      expect(chat.admin?(members(:alice_team_member))).to be true
      end
      
    it 'participant has limited access' do
      chat = chats(:team_chat)
      expect(chat.owner?(members(:bob_team_member))).to be false
      expect(chat.member_exists?(members(:bob_team_member))).to be true
      expect(chat.admin?(members(:bob_team_member))).to be false
    end

    it 'non-participant has no access' do
      expect(chats(:team_chat).member_exists?(members(:bob_personal_member))).to be false
    end
  end
  
  describe 'scopes' do
    it 'filters by member count' do
      expect(Chat.personal).to include(chats(:alice_personal_chat))
      expect(Chat.with_multiple_members).to include(chats(:team_chat))
    end
  end

  describe '#recover_from_tool_errors!' do
    let(:chat) { chats(:team_chat) }

    context 'when no broken tool chains exist' do
      it 'returns false and modifies nothing' do
        expect(chat.recover_from_tool_errors!).to be false
      end
    end

    context 'with incomplete tool chain (missing tool results)' do
      it 'marks the assistant message and existing tool results as skip_llm_context' do
        # Create assistant message with 2 tool calls
        assistant_msg = chat.messages.create!(
          role: :assistant,
          content: "",
          user_submitted: false
        )

        tc1 = ToolCall.create!(
          message: assistant_msg,
          tool_call_id: "call_1",
          name: "search",
          arguments: "{}"
        )
        tc2 = ToolCall.create!(
          message: assistant_msg,
          tool_call_id: "call_2",
          name: "read_file",
          arguments: "{}"
        )

        # Only 1 of 2 tool results arrived (simulates crash mid-execution)
        chat.messages.create!(
          role: :tool,
          content: "search result",
          tool_call_id: tc1.id,
          user_submitted: false
        )

        result = chat.recover_from_tool_errors!

        expect(result).to be true
        expect(assistant_msg.reload.skip_llm_context).to be true
      end
    end

    context 'with orphaned tool results (tool_call_id = nil)' do
      it 'marks orphaned tool messages as skip_llm_context' do
        orphaned_msg = chat.messages.create!(
          role: :tool,
          content: "orphaned result",
          tool_call_id: nil,
          user_submitted: false
        )

        result = chat.recover_from_tool_errors!

        expect(result).to be true
        expect(orphaned_msg.reload.skip_llm_context).to be true
      end
    end

    context 'with already-skipped messages' do
      it 'does not double-process already-skipped messages' do
        chat.messages.create!(
          role: :tool,
          content: "already skipped",
          tool_call_id: nil,
          user_submitted: false,
          skip_llm_context: true
        )

        expect(chat.recover_from_tool_errors!).to be false
      end
    end
  end

  describe '#order_messages_for_llm' do
    let(:chat) { chats(:team_chat) }

    it 'excludes messages marked skip_llm_context' do
      normal_msg = chat.messages.create!(
        role: :user,
        content: "Normal message",
        user: users(:alice),
        member: members(:alice_team_member),
        user_submitted: true
      )
      skipped_msg = chat.messages.create!(
        role: :assistant,
        content: "Should be skipped",
        user_submitted: false,
        skip_llm_context: true
      )

      messages = chat.messages.where(id: [normal_msg.id, skipped_msg.id])
      filtered = chat.order_messages_for_llm(messages)

      expect(filtered.map(&:id)).to include(normal_msg.id)
      expect(filtered.map(&:id)).not_to include(skipped_msg.id)
    end

    it 'excludes empty non-system assistant messages (cancelled runs)' do
      empty_assistant = chat.messages.create!(
        role: :assistant,
        content: "",
        user_submitted: false
      )

      messages = chat.messages.where(id: empty_assistant.id)
      filtered = chat.order_messages_for_llm(messages)

      expect(filtered.map(&:id)).not_to include(empty_assistant.id)
    end

    it 'preserves tool role messages even if content is empty' do
      tc = ToolCall.create!(
        message: chat.messages.create!(role: :assistant, content: "use tool", user_submitted: false),
        tool_call_id: "call_keep",
        name: "test",
        arguments: "{}"
      )

      tool_msg = chat.messages.create!(
        role: :tool,
        content: "",
        tool_call_id: tc.id,
        user_submitted: false
      )

      messages = chat.messages.where(id: tool_msg.id)
      filtered = chat.order_messages_for_llm(messages)

      expect(filtered.map(&:id)).to include(tool_msg.id)
    end
  end
end
