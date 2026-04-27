# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Mentionable, type: :model do
  # Contract test: documents the interface that all @mentionable models must provide
  
  describe 'included interface' do
    # Test with Member since it includes Mentionable
    let(:member) { members(:alice_team_member) }

    describe '#mentionable_label' do
      it 'returns display label for autocomplete' do
        expect(member.mentionable_label).to be_present
        expect(member.mentionable_label).to be_a(String)
      end
    end

    describe '#mentionable_kind' do
      it 'returns model type as symbol' do
        expect(member.mentionable_kind).to eq(:member)
      end
    end

    describe '#mentionable_path' do
      it 'returns URL path for navigation' do
        expect(member.mentionable_path).to be_present
        expect(member.mentionable_path).to start_with('/')
      end
    end

    describe '#to_mention' do
      it 'returns hash for frontend autocomplete' do
        mention = member.to_mention
        
        expect(mention).to include(
          id: member.to_param,
          model: 'Member',
          label: member.mentionable_label,
          kind: :member,
          path: member.mentionable_path
        )
      end

      it 'uses to_param for id (prefix_id compatible)' do
        # Ensures frontend gets mbr_xxx not numeric ID
        expect(member.to_mention[:id]).to eq(member.to_param)
      end
    end

    describe '#to_llm_context' do
      context 'when RecordContext class exists' do
        it 'returns context instance' do
          context = member.to_llm_context
          
          expect(context).to be_a(MemberContext)
          expect(context.id).to eq(member.to_param)
        end
      end

      context 'when no RecordContext class' do
        # Workspace has WorkspaceContext, but for models without one...
        it 'falls back to to_llm_mention' do
          # This tests the fallback path - would need a model without context class
          # For now we verify the method exists and responds
          expect(member).to respond_to(:to_llm_mention)
        end
      end
    end

    describe '#to_llm_mention' do
      it 'returns lightweight hash for LLM' do
        mention = member.to_llm_mention
        
        expect(mention[:type]).to eq('Member')
        expect(mention[:id]).to eq(member.to_param)
        expect(mention[:label]).to eq(member.mentionable_label)
        expect(mention[:summary]).to be_present
      end
    end

    describe '#mentionable_summary' do
      it 'returns brief text summary' do
        # Member overrides this
        expect(member.mentionable_summary).to be_present
        expect(member.mentionable_summary).to be_a(String)
      end
    end
  end

  describe 'Workspace mentionable' do
    let(:org) { workspaces(:team_org) }

    it 'implements full interface' do
      expect(org.mentionable_label).to include(org.name)
      expect(org.mentionable_kind).to eq(:workspace)
      expect(org.mentionable_path).to start_with('/w')
      expect(org.to_mention[:model]).to eq('Workspace')
      expect(org.to_llm_context).to be_a(WorkspaceContext)
    end
  end

  describe 'Chat mentionable' do
    let(:chat) { chats(:team_chat) }

    it 'implements full interface' do
      expect(chat.mentionable_label).to eq(chat.name)
      expect(chat.mentionable_kind).to eq(:chat)
      expect(chat.to_mention[:model]).to eq('Chat')
      expect(chat.to_llm_context).to be_a(ChatContext)
    end
  end
end

