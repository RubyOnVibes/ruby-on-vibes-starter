# frozen_string_literal: true

require 'rails_helper'

RSpec.describe WorkspaceContext, type: :model do
  # Contract test: documents what data the LLM receives when an Workspace is @mentioned
  
  describe '.from_record' do
    context 'team workspace' do
      let(:org) { workspaces(:team_org) }
      let(:context) { described_class.from_record(org) }

      it 'serializes workspace identity' do
        expect(context.id).to eq(org.to_param)
        expect(context.name).to eq(org.name)
      end

      it 'serializes clickable path' do
        # LLM uses this for markdown links: [Acme Corp](/workspaces/ws_xxx)
        expect(context.path).to eq(org.mentionable_path)
        expect(context.path).to start_with('/workspaces')
      end

      it 'serializes type as team' do
        expect(context.type).to eq('team')
      end

      it 'serializes members_count' do
        expect(context.members_count).to eq(org.members_count)
        expect(context.members_count).to be >= 0
      end

      it 'serializes owner username' do
        expect(context.owner_username).to eq(org.owner.username)
      end
    end

    context 'personal workspace' do
      let(:org) { workspaces(:alice_personal) }
      let(:context) { described_class.from_record(org) }

      it 'serializes type as personal' do
        expect(context.type).to eq('personal')
      end
    end
  end

  describe '#summary' do
    it 'returns human-readable summary for team' do
      org = workspaces(:team_org)
      context = described_class.from_record(org)
      
      summary = context.summary
      expect(summary).to include('Team')
      expect(summary).to include(org.name)
      expect(summary).to include('members')
      expect(summary).to include(org.owner.username)
    end

    it 'returns human-readable summary for personal' do
      org = workspaces(:alice_personal)
      context = described_class.from_record(org)
      
      summary = context.summary
      expect(summary).to include('Personal')
    end
  end

  describe 'schema validation' do
    it 'requires id field' do
      expect {
        described_class.new(name: 'Test')
      }.to raise_error(ArgumentError, /Missing required field 'id'/)
    end
  end

  describe 'JSON schema' do
    let(:context) { described_class.from_record(workspaces(:team_org)) }

    it 'exports valid JSON schema with enum' do
      schema = context.to_json_schema
      
      # Schema name represents the model, not the Context wrapper
      expect(schema[:name]).to eq('Workspace')
      expect(schema[:schema][:properties][:type][:enum]).to eq(%w[personal team])
      expect(schema[:schema][:properties][:members_count][:minimum]).to eq(0)
    end
  end
end

