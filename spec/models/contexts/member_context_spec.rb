# frozen_string_literal: true

require 'rails_helper'

RSpec.describe MemberContext, type: :model do
  # Contract test: documents what data the LLM receives when a Member is @mentioned
  
  describe '.from_record' do
    let(:member) { members(:alice_team_member) }
    let(:context) { described_class.from_record(member) }

    it 'serializes member identity' do
      expect(context.id).to eq(member.to_param)
      expect(context.name).to eq(member.user.name)
      expect(context.username).to eq(member.user.username)
    end

    it 'serializes clickable path' do
      # LLM uses this path for markdown links: [Alice](/members/mbr_xxx)
      expect(context.path).to eq(member.mentionable_path)
      expect(context.path).to start_with('/members/')
    end

    it 'serializes workspace context' do
      expect(context.workspace[:id]).to eq(member.workspace.to_param)
      expect(context.workspace[:name]).to eq(member.workspace.name)
      expect(context.workspace[:type]).to be_in(%w[personal team])
    end

    it 'serializes roles array' do
      expect(context.roles).to be_an(Array)
      # alice_team_member has admin: true, which translates to roles
      # Note: active_roles depends on Workspace::Roles implementation
    end

    it 'serializes ownership status' do
      # alice owns team_org
      expect(context.is_owner).to be true
    end

    context 'non-owner member' do
      let(:member) { members(:bob_team_member) }

      it 'is_owner is false' do
        expect(context.is_owner).to be false
      end
    end
  end

  describe '#summary' do
    it 'returns human-readable summary' do
      member = members(:alice_team_member)
      context = described_class.from_record(member)
      
      summary = context.summary
      expect(summary).to include(member.user.name)
      expect(summary).to include(member.workspace.name)
    end
  end

  describe 'schema validation' do
    it 'requires id field' do
      expect {
        described_class.new(name: 'Test', workspace: {}, roles: [])
      }.to raise_error(ArgumentError, /Missing required field 'id'/)
    end

    it 'requires workspace field' do
      expect {
        described_class.new(id: 'mbr_xxx', name: 'Test', roles: [])
      }.to raise_error(ArgumentError, /Missing required field/)
    end
  end

  describe 'JSON schema' do
    let(:context) { described_class.from_record(members(:alice_team_member)) }

    it 'exports valid JSON schema' do
      schema = context.to_json_schema
      
      # Schema name represents the model, not the Context wrapper
      expect(schema[:name]).to eq('Member')
      expect(schema[:description]).to be_present
      expect(schema[:schema][:type]).to eq('object')
      expect(schema[:schema][:properties]).to include(:id, :name, :path, :workspace, :roles, :is_owner)
    end
  end
end

