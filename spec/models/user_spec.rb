# frozen_string_literal: true

require 'rails_helper'

RSpec.describe User, type: :model do
  describe 'validations' do
    it 'requires email' do
      user = User.new(password: 'password123', first_name: 'Test')
      expect(user).not_to be_valid
      expect(user.errors[:email]).to be_present
    end

    it 'requires unique email' do
      user = User.new(email: users(:alice).email, password: 'password123', first_name: 'Dup')
      expect(user).not_to be_valid
    end

    it 'requires valid username format' do
      users(:alice).username = 'Invalid Name!'
      expect(users(:alice)).not_to be_valid
    end
  end

  describe 'associations' do
    it 'has workspaces through members' do
      expect(users(:alice).workspaces).to include(workspaces(:alice_personal))
    end
  end

  describe '#name' do
    it 'returns full name' do
      expect(users(:alice).name).to eq('Alice Smith')
    end
  end

  describe '#create_personal_workspace' do
    it 'names personal orgs "Personal Workspace"' do
      user = users(:alice)
      personal_org = user.personal_workspace
      
      # All personal orgs have same name for simplicity
      expect(personal_org.name).to eq('Personal Workspace')
      expect(personal_org.personal?).to be true
    end
  end
end
