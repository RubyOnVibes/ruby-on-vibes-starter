# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Member, type: :model do
  describe 'validations' do
    it 'requires unique user per workspace' do
      member = Member.new(user: users(:alice), workspace: workspaces(:alice_personal))
      expect(member).not_to be_valid
    end
  end

  describe 'associations' do
    it 'belongs to user and workspace' do
      member = members(:alice_personal_member)
      expect(member.user).to eq(users(:alice))
      expect(member.workspace).to eq(workspaces(:alice_personal))
    end
  end

  describe '#workspace_owner?' do
    it 'returns true when user owns the workspace' do
      expect(members(:alice_team_member).workspace_owner?).to be true
      expect(members(:bob_team_member).workspace_owner?).to be false
    end
  end
end
