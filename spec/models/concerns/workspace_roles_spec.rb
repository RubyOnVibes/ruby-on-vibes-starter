# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Workspace::Roles, type: :model do
  # Test using Member which includes Workspace::Roles

  describe 'ROLES constant' do
    it 'defines available roles' do
      expect(Member::ROLES).to be_an(Array)
      expect(Member::ROLES).to include(:admin)
      expect(Member::ROLES).to include(:member)
    end

    it 'is accessible on the including class' do
      expect(Member::ROLES).to eq(Workspace::Roles::ROLES)
    end

    it 'is frozen to prevent modification' do
      expect(Workspace::Roles::ROLES).to be_frozen
    end
  end

  describe 'store_accessor' do
    it 'creates accessors for all roles' do
      member = Member.new
      Workspace::Roles::ROLES.each do |role|
        expect(member).to respond_to(role)
        expect(member).to respond_to(:"#{role}=")
        expect(member).to respond_to(:"#{role}?")
      end
    end
  end

  describe 'role accessors' do
    let(:member) { members(:bob_team_member) }

    it 'can set and get admin role' do
      member.admin = true
      expect(member.admin).to be true
      expect(member.admin?).to be true
    end

    it 'can set and get member role' do
      member.member = true
      expect(member.member).to be true
      expect(member.member?).to be true
    end

    it 'casts string values to booleans' do
      member.admin = "1"
      expect(member.admin).to be true

      member.admin = "0"
      expect(member.admin).to be false

      member.admin = "true"
      expect(member.admin).to be true

      member.admin = "false"
      expect(member.admin).to be false
    end

    it 'casts nil to false' do
      member.admin = nil
      expect(member.admin).to be_falsey
    end
  end

  describe 'role scopes' do
    before do
      members(:alice_team_member).update!(admin: true, member: true)
      members(:bob_team_member).update!(admin: false, member: true)
    end

    it 'scopes by admin role' do
      admins = Member.admin
      expect(admins).to include(members(:alice_team_member))
      expect(admins).not_to include(members(:bob_team_member))
    end

    it 'scopes by member role' do
      members_with_role = Member.member
      expect(members_with_role).to include(members(:alice_team_member))
      expect(members_with_role).to include(members(:bob_team_member))
    end

    it 'works with chained scopes' do
      # Ensure scopes can be combined with other AR methods
      admin_in_workspace = Member.admin.where(workspace: workspaces(:team_org))
      expect(admin_in_workspace).to include(members(:alice_team_member))
    end
  end

  describe '.role_query_condition' do
    it 'returns a valid SQL condition array' do
      condition = Member.role_query_condition(:admin)
      expect(condition).to be_an(Array)
      expect(condition.first).to be_a(String)
      expect(condition.length).to be >= 2
    end

    it 'adapts to the database adapter' do
      condition = Member.role_query_condition(:admin)
      adapter = ActiveRecord::Base.configurations.find_db_config(Rails.env)&.adapter

      if adapter&.include?('postgresql')
        expect(condition.first).to include('@>')
      elsif adapter&.include?('sqlite')
        expect(condition.first).to include('json_extract')
      end
    end
  end

  describe '#active_roles' do
    let(:member) { members(:bob_team_member) }

    it 'returns empty array when no roles set' do
      member.update!(admin: false, member: false)
      expect(member.active_roles).to eq([])
    end

    it 'returns array of active role symbols' do
      member.update!(admin: true, member: true)
      expect(member.active_roles).to contain_exactly(:admin, :member)
    end

    it 'only includes roles that are true' do
      member.update!(admin: true, member: false)
      expect(member.active_roles).to eq([:admin])
    end
  end

  describe 'persistence' do
    let(:member) { members(:bob_team_member) }

    it 'persists role changes to database' do
      member.update!(admin: true, member: true)
      member.reload

      expect(member.admin?).to be true
      expect(member.member?).to be true
    end

    it 'stores roles in jsonb column' do
      member.update!(admin: true, member: false)

      # Verify the raw jsonb structure
      raw_roles = member.read_attribute(:roles)
      expect(raw_roles).to be_a(Hash)
      expect(raw_roles['admin']).to be true
    end
  end
end
