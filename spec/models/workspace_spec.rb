# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Workspace, type: :model do
  describe 'validations' do
    it 'requires name' do
      org = Workspace.new(owner: users(:alice))
      expect(org).not_to be_valid
    end

    it 'requires unique name per owner' do
      org = Workspace.new(name: workspaces(:alice_personal).name, owner: users(:alice))
      expect(org).not_to be_valid
    end
  end

  describe 'associations' do
    it 'belongs to owner' do
      expect(workspaces(:alice_personal).owner).to eq(users(:alice))
    end

    it 'has many members' do
      expect(workspaces(:team_org).members.count).to eq(2)
    end

    it 'has users through members' do
      expect(workspaces(:team_org).users).to include(users(:alice), users(:bob))
    end
  end

  describe '#personal? / #team?' do
    it 'distinguishes personal from team orgs' do
      expect(workspaces(:alice_personal).personal?).to be true
      expect(workspaces(:team_org).team?).to be true
      expect(workspaces(:alice_personal).team?).to be false
      expect(workspaces(:team_org).personal?).to be false
    end
  end

  describe '#email' do
    it 'returns billing_email if set, else owner email' do
      expect(workspaces(:team_org).email).to eq('billing@acme.example.com')
      expect(workspaces(:alice_personal).email).to eq(users(:alice).email)
    end
  end

  describe '#billing_contact' do
    it 'returns billing_email when set' do
      workspace = workspaces(:team_org)
      expect(workspace.billing_contact).to eq('billing@acme.example.com')
    end

    it 'falls back to owner email when billing_email not set' do
      workspace = workspaces(:alice_personal)
      expect(workspace.billing_contact).to eq(users(:alice).email)
    end
  end

  describe '#per_unit_quantity' do
    it 'returns the member count for per-seat billing' do
      expect(workspaces(:team_org).per_unit_quantity).to eq(2)
      expect(workspaces(:alice_personal).per_unit_quantity).to eq(1)
    end
  end

  describe '#billable_name' do
    it 'returns workspace name for billing display' do
      expect(workspaces(:team_org).billable_name).to eq('Acme Corp')
    end
  end

  describe 'Pay integration' do
    it 'includes pay_customer' do
      # Pay gem adds these modules when pay_customer is called
      expect(Workspace.ancestors.map(&:to_s)).to include('Pay::Billable::SyncCustomer')
    end

    it 'responds to payment_processor' do
      expect(workspaces(:team_org)).to respond_to(:payment_processor)
    end
  end
end
