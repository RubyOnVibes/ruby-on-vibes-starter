# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Current, type: :model do
  after do
    Current.reset
  end

  describe 'attributes' do
    it 'has user attribute' do
      Current.user = users(:alice)
      expect(Current.user).to eq(users(:alice))
    end

    it 'has workspace attribute' do
      Current.workspace = workspaces(:team_org)
      expect(Current.workspace).to eq(workspaces(:team_org))
    end

    it 'has request_id attribute' do
      Current.request_id = 'abc-123'
      expect(Current.request_id).to eq('abc-123')
    end

    it 'has ip_address attribute' do
      Current.ip_address = '127.0.0.1'
      expect(Current.ip_address).to eq('127.0.0.1')
    end

    it 'has user_agent attribute' do
      Current.user_agent = 'Mozilla/5.0'
      expect(Current.user_agent).to eq('Mozilla/5.0')
    end
  end

  describe '#user=' do
    it 'sets time zone from user preference' do
      users(:alice).update!(time_zone: 'America/New_York')
      Current.user = users(:alice)

      expect(Time.zone.name).to eq('America/New_York')
    end

    it 'handles nil user gracefully' do
      expect { Current.user = nil }.not_to raise_error
    end
  end

  describe '#workspace=' do
    it 'clears cached member when workspace changes' do
      Current.user = users(:alice)
      Current.workspace = workspaces(:team_org)

      # Access member to cache it
      _cached = Current.member

      # Change workspace
      Current.workspace = workspaces(:alice_personal)

      # Member should be re-fetched for new workspace
      expect(Current.member.workspace).to eq(workspaces(:alice_personal))
    end

    it 'clears cached other_workspaces when workspace changes' do
      Current.user = users(:alice)
      Current.workspace = workspaces(:team_org)

      # Access to cache
      _cached = Current.other_workspaces

      # Change workspace
      Current.workspace = workspaces(:alice_personal)

      # other_workspaces should not include new current workspace
      expect(Current.other_workspaces).not_to include(workspaces(:alice_personal))
    end
  end

  describe '#member' do
    it 'returns nil without user' do
      Current.workspace = workspaces(:team_org)
      expect(Current.member).to be_nil
    end

    it 'returns nil without workspace' do
      Current.user = users(:alice)
      expect(Current.member).to be_nil
    end

    it 'returns the member for current user in current workspace' do
      Current.user = users(:alice)
      Current.workspace = workspaces(:team_org)

      expect(Current.member).to eq(members(:alice_team_member))
    end

    it 'caches the member lookup' do
      Current.user = users(:alice)
      Current.workspace = workspaces(:team_org)

      # First call fetches and caches
      member1 = Current.member

      # Second call returns same object (cached via instance variable)
      member2 = Current.member

      expect(member1).to eq(member2)
      expect(member1.object_id).to eq(member2.object_id)
    end
  end

  describe '#roles' do
    it 'returns empty array without member' do
      Current.user = users(:alice)
      # No workspace set
      expect(Current.roles).to eq([])
    end

    it 'returns active roles from member' do
      members(:alice_team_member).update!(admin: true, member: true)

      Current.user = users(:alice)
      Current.workspace = workspaces(:team_org)

      expect(Current.roles).to contain_exactly(:admin, :member)
    end
  end

  describe '#admin?' do
    it 'returns false without member' do
      Current.user = users(:alice)
      expect(Current.admin?).to be false
    end

    it 'returns true when member has admin role' do
      members(:alice_team_member).update!(admin: true)

      Current.user = users(:alice)
      Current.workspace = workspaces(:team_org)

      expect(Current.admin?).to be true
    end

    it 'returns false when member lacks admin role' do
      members(:bob_team_member).update!(admin: false)

      Current.user = users(:bob)
      Current.workspace = workspaces(:team_org)

      expect(Current.admin?).to be false
    end
  end

  describe '#workspace_owner?' do
    it 'returns false without workspace' do
      Current.user = users(:alice)
      expect(Current.workspace_owner?).to be false
    end

    it 'returns true when user owns the workspace' do
      Current.user = users(:alice)
      Current.workspace = workspaces(:team_org) # alice owns team_org

      expect(Current.workspace_owner?).to be true
    end

    it 'returns false when user does not own the workspace' do
      Current.user = users(:bob)
      Current.workspace = workspaces(:team_org) # alice owns team_org

      expect(Current.workspace_owner?).to be false
    end
  end

  describe '#can_manage_workspace?' do
    it 'returns true for workspace owner' do
      Current.user = users(:alice)
      Current.workspace = workspaces(:team_org)

      expect(Current.can_manage_workspace?).to be true
    end

    it 'returns true for admin member' do
      members(:bob_team_member).update!(admin: true)

      Current.user = users(:bob)
      Current.workspace = workspaces(:team_org)

      expect(Current.can_manage_workspace?).to be true
    end

    it 'returns false for non-admin member' do
      members(:bob_team_member).update!(admin: false)

      Current.user = users(:bob)
      Current.workspace = workspaces(:team_org)

      expect(Current.can_manage_workspace?).to be false
    end
  end

  describe '#other_workspaces' do
    it 'returns empty relation without user' do
      Current.workspace = workspaces(:team_org)
      expect(Current.other_workspaces).to be_empty
    end

    it 'returns user workspaces excluding current one' do
      Current.user = users(:alice)
      Current.workspace = workspaces(:team_org)

      other = Current.other_workspaces

      expect(other).to include(workspaces(:alice_personal))
      expect(other).not_to include(workspaces(:team_org))
    end

    it 'orders by id ascending' do
      Current.user = users(:alice)
      Current.workspace = workspaces(:alice_personal)

      expect(Current.other_workspaces.to_sql).to include('ORDER BY')
    end
  end

  describe 'reset' do
    it 'clears all attributes' do
      Current.user = users(:alice)
      Current.workspace = workspaces(:team_org)
      Current.request_id = 'test'

      Current.reset

      expect(Current.user).to be_nil
      expect(Current.workspace).to be_nil
      expect(Current.request_id).to be_nil
    end

    it 'resets time zone' do
      users(:alice).update!(time_zone: 'America/New_York')
      Current.user = users(:alice)

      Current.reset

      # Time.zone should be reset (back to default or nil)
      expect(Time.zone.name).not_to eq('America/New_York')
    end
  end
end
