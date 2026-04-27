# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Message, type: :model do
  describe 'associations' do
    it 'belongs to chat' do
      message = messages(:alice_message)
      expect(message.chat).to eq(chats(:alice_personal_chat))
    end

    it 'belongs to user (optional)' do
      message = messages(:alice_message)
      expect(message.user).to eq(users(:alice))
    end

    it 'belongs to member (optional)' do
      message = messages(:alice_message)
      expect(message.member).to eq(members(:alice_personal_member))
    end
  end

  describe 'validations' do
    it 'requires user_id for user_submitted messages' do
      message = Message.new(
        chat: chats(:alice_personal_chat),
        role: 'user',
        user_submitted: true,
        content: 'test'
      )
      expect(message).not_to be_valid
      expect(message.errors[:user_id]).to be_present
    end

    it 'requires member_id for user_submitted messages' do
      message = Message.new(
        chat: chats(:alice_personal_chat),
        role: 'user',
        user_submitted: true,
        user: users(:alice),
        content: 'test'
      )
      expect(message).not_to be_valid
      expect(message.errors[:member_id]).to be_present
    end

    it 'validates member belongs to user' do
      message = Message.new(
        chat: chats(:alice_personal_chat),
        role: 'user',
        user_submitted: true,
        user: users(:alice),
        member: members(:bob_personal_member),  # Wrong member!
        content: 'test'
      )
      expect(message).not_to be_valid
      expect(message.errors[:member]).to be_present
    end
  end

  describe '#to_llm' do
    context 'single-member chat' do
      it 'prefixes with user identity' do
        message = messages(:alice_message)
        llm_msg = message.to_llm        
        expect(llm_msg.content).to eq('Hello from Alice')
      end
    end

    # TODO: add mentionable tests
  end
end

