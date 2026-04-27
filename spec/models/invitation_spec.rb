# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Invitation, type: :model do
  let(:workspace) { workspaces(:team_org) }
  let(:originator) { users(:alice) }

  describe 'validations' do
    it 'requires name' do
      invitation = Invitation.new(
        email: 'new@example.com',
        workspace: workspace,
        originator: originator
      )
      expect(invitation).not_to be_valid
      expect(invitation.errors[:name]).to be_present
    end

    it 'requires email' do
      invitation = Invitation.new(
        name: 'New User',
        workspace: workspace,
        originator: originator
      )
      expect(invitation).not_to be_valid
      expect(invitation.errors[:email]).to be_present
    end

    it 'requires unique email per workspace' do
      Invitation.create!(
        name: 'First',
        email: 'duplicate@example.com',
        workspace: workspace,
        originator: originator
      )

      duplicate = Invitation.new(
        name: 'Second',
        email: 'duplicate@example.com',
        workspace: workspace,
        originator: originator
      )
      expect(duplicate).not_to be_valid
      expect(duplicate.errors[:email]).to be_present
    end

    it 'allows same email in different workspaces' do
      other_workspace = workspaces(:alice_personal)

      Invitation.create!(
        name: 'First',
        email: 'shared@example.com',
        workspace: workspace,
        originator: originator
      )

      other_invite = Invitation.new(
        name: 'Second',
        email: 'shared@example.com',
        workspace: other_workspace,
        originator: originator
      )
      expect(other_invite).to be_valid
    end
  end

  describe 'associations' do
    let(:invitation) do
      Invitation.create!(
        name: 'Test User',
        email: 'test@example.com',
        workspace: workspace,
        originator: originator
      )
    end

    it 'belongs to workspace' do
      expect(invitation.workspace).to eq(workspace)
    end

    it 'belongs to originator' do
      expect(invitation.originator).to eq(originator)
    end
  end

  describe 'token' do
    let(:invitation) do
      Invitation.create!(
        name: 'Test User',
        email: 'test@example.com',
        workspace: workspace,
        originator: originator
      )
    end

    it 'generates a secure token on create' do
      expect(invitation.token).to be_present
      expect(invitation.token.length).to be >= 20
    end

    it 'uses token as param' do
      expect(invitation.to_param).to eq(invitation.token)
    end
  end

  describe 'roles' do
    let(:invitation) do
      Invitation.create!(
        name: 'Test User',
        email: 'test@example.com',
        workspace: workspace,
        originator: originator,
        admin: true,
        member: true
      )
    end

    it 'includes Workspace::Roles' do
      expect(Invitation.ancestors).to include(Workspace::Roles)
    end

    it 'can have roles assigned' do
      expect(invitation.admin?).to be true
      expect(invitation.member?).to be true
    end
  end

  describe '#accept!' do
    let(:new_user) do
      User.create!(
        email: 'newuser@example.com',
        password: 'password123',
        first_name: 'New',
        last_name: 'User',
        username: 'newuser'
      )
    end

    let(:invitation) do
      Invitation.create!(
        name: 'New User',
        email: 'newuser@example.com',
        workspace: workspace,
        originator: originator,
        admin: false,
        member: true
      )
    end

    it 'creates a member with invitation roles' do
      member = invitation.accept!(new_user)

      expect(member).to be_a(Member)
      expect(member).to be_persisted
      expect(member.user).to eq(new_user)
      expect(member.workspace).to eq(workspace)
      expect(member.member?).to be true
      expect(member.admin?).to be false
    end

    it 'destroys the invitation' do
      invitation.accept!(new_user)
      expect { invitation.reload }.to raise_error(ActiveRecord::RecordNotFound)
    end

    it 'raises error if email does not match' do
      other_user = users(:bob)
      expect { invitation.accept!(other_user) }.to raise_error("Email does not match")
    end

    it 'returns nil and adds error on failure' do
      # Create a member first so acceptance fails on uniqueness
      workspace.members.create!(user: new_user)

      result = invitation.accept!(new_user)
      expect(result).to be_nil
      expect(invitation.errors[:base]).to be_present
    end

    it 'performs member creation and invitation destruction atomically' do
      member = invitation.accept!(new_user)

      # Both operations succeeded together
      expect(member).to be_persisted
      expect { invitation.reload }.to raise_error(ActiveRecord::RecordNotFound)
    end
  end

  describe '#deliver' do
    let(:invitation) do
      Invitation.create!(
        name: 'Test User',
        email: 'test@example.com',
        workspace: workspace,
        originator: originator
      )
    end

    it 'returns true' do
      # Stub mailer to avoid actual delivery
      allow(InvitationsMailer).to receive_message_chain(:with, :invite_email, :deliver_later)
      expect(invitation.deliver).to be true
    end

    context 'when invitee is an existing user' do
      let(:existing_user) { users(:bob) }
      let(:invitation_to_existing) do
        Invitation.create!(
          name: 'Bob Jones',
          email: existing_user.email,
          workspace: workspace,
          originator: originator
        )
      end

      it 'sends in-app notification instead of email' do
        notifier_double = instance_double(InvitationNotifier)
        allow(InvitationNotifier).to receive(:with).and_return(notifier_double)
        allow(notifier_double).to receive(:deliver)

        invitation_to_existing.deliver

        expect(InvitationNotifier).to have_received(:with).with(
          hash_including(invitation: invitation_to_existing)
        )
        expect(notifier_double).to have_received(:deliver).with(existing_user)
      end
    end

    context 'when invitee is a new user' do
      it 'sends email invitation' do
        mailer_double = double(deliver_later: true)
        allow(InvitationsMailer).to receive_message_chain(:with, :invite_email).and_return(mailer_double)

        invitation.deliver

        expect(mailer_double).to have_received(:deliver_later)
      end
    end
  end

  describe '#reject!' do
    let(:invitation) do
      Invitation.create!(
        name: 'Test User',
        email: 'reject@example.com',
        workspace: workspace,
        originator: originator
      )
    end

    it 'destroys the invitation' do
      invitation.reject!
      expect { invitation.reload }.to raise_error(ActiveRecord::RecordNotFound)
    end

    it 'returns the destroyed invitation' do
      result = invitation.reject!
      expect(result).to be_destroyed
    end
  end

  describe 'email normalization' do
    it 'downcases email before validation' do
      invitation = Invitation.create!(
        name: 'Test User',
        email: 'TEST@EXAMPLE.COM',
        workspace: workspace,
        originator: originator
      )
      expect(invitation.email).to eq('test@example.com')
    end
  end
end
