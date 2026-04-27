# frozen_string_literal: true

require 'rails_helper'

RSpec.describe ChatContext, type: :model do
  # Contract test: documents what data the LLM receives when a Chat is @mentioned
  
  describe '.from_record' do
    let(:chat) { chats(:team_chat) }
    let(:context) { described_class.from_record(chat) }

    it 'serializes chat identity' do
      expect(context.id).to eq(chat.to_param)
      expect(context.name).to eq(chat.name)
    end

    it 'serializes clickable path' do
      # LLM uses this for markdown links
      expect(context.path).to be_present
      expect(context.path).to include(chat.to_param)
    end

    it 'serializes messages_count' do
      expect(context.messages_count).to eq(chat.messages.count)
      expect(context.messages_count).to be >= 0
    end

    it 'serializes timestamps' do
      expect(context.created_at).to match(/\d{4}-\d{2}-\d{2}T/)  # ISO8601
      expect(context.updated_at).to match(/\d{4}-\d{2}-\d{2}T/)
    end

    it 'serializes owner member info' do
      expect(context.member[:id]).to eq(chat.member.to_param)
      expect(context.member[:user_name]).to be_present
    end

    context 'chat without AI model' do
      # Most chats in fixtures don't have a model assigned
      it 'omits model field when nil' do
        expect(context.data).not_to have_key(:model)
      end
    end

    context 'chat with AI model' do
      before do
        # Stub the model association
        model_double = double(
          model_id: 'claude-sonnet-4-20250514',
          name: 'Claude Sonnet 4',
          provider: 'anthropic'
        )
        allow(chat).to receive(:model).and_return(model_double)
      end

      it 'serializes model info' do
        context = described_class.from_record(chat)
        
        expect(context.model[:id]).to eq('claude-sonnet-4-20250514')
        expect(context.model[:name]).to eq('Claude Sonnet 4')
        expect(context.model[:provider]).to eq('anthropic')
      end
    end
  end

  describe '#summary' do
    it 'returns human-readable summary' do
      chat = chats(:team_chat)
      context = described_class.from_record(chat)
      
      summary = context.summary
      expect(summary).to include('Chat')
      expect(summary).to include(chat.name)
      expect(summary).to include('messages')
    end
  end

  describe 'schema validation' do
    it 'requires id field' do
      expect {
        described_class.new(name: 'Test')
      }.to raise_error(ArgumentError, /Missing required field 'id'/)
    end

    it 'requires member field' do
      expect {
        described_class.new(
          id: 'chat_xxx',
          name: 'Test',
          path: '/test',
          messages_count: 0,
          created_at: Time.current.iso8601,
          updated_at: Time.current.iso8601
        )
      }.to raise_error(ArgumentError, /Missing required field 'member'/)
    end
  end

  describe 'JSON schema' do
    let(:context) { described_class.from_record(chats(:team_chat)) }

    it 'exports valid JSON schema' do
      schema = context.to_json_schema
      
      # Schema name represents the model, not the Context wrapper
      expect(schema[:name]).to eq('Chat')
      expect(schema[:schema][:properties][:messages_count][:minimum]).to eq(0)
      # Model should not be in required
      required = schema[:schema][:required] || []
      expect(required).not_to include('model')
    end
  end
end

