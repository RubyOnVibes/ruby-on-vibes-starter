# frozen_string_literal: true

require 'rails_helper'

RSpec.describe ChatInvitation, type: :model do
  let(:chat) { chats(:team_chat) }
  let(:inviter) { members(:alice_team_member) }
  let(:invitee) { members(:bob_personal_member) } # Not already a chat member

  describe 'validations' do
    it 'cannot invite yourself' do
      invitation = ChatInvitation.new(
        chat: chat,
        inviter: inviter,
        invitee: inviter
      )
      expect(invitation).not_to be_valid
      expect(invitation.errors[:invitee]).to include("cannot invite yourself")
    end

    it 'cannot invite an existing chat member' do
      invitation = ChatInvitation.new(
        chat: chat,
        inviter: inviter,
        invitee: members(:bob_team_member) # Already a chat_member via fixture
      )
      expect(invitation).not_to be_valid
      expect(invitation.errors[:invitee]).to include("is already a member of this chat")
    end

    it 'cannot create duplicate pending invitation' do
      # Stub notification to avoid Noticed dependency
      allow_any_instance_of(ChatInvitation).to receive(:send_notification)

      ChatInvitation.create!(
        chat: chat,
        inviter: inviter,
        invitee: invitee,
        status: :pending
      )

      duplicate = ChatInvitation.new(
        chat: chat,
        inviter: inviter,
        invitee: invitee
      )
      expect(duplicate).not_to be_valid
      expect(duplicate.errors[:invitee].first).to include("has already been invited")
    end

    it 'cannot invite member who already accepted' do
      allow_any_instance_of(ChatInvitation).to receive(:send_notification)

      ChatInvitation.create!(
        chat: chat,
        inviter: inviter,
        invitee: invitee,
        status: :accepted,
        responded_at: Time.current
      )

      new_invite = ChatInvitation.new(
        chat: chat,
        inviter: inviter,
        invitee: invitee
      )
      expect(new_invite).not_to be_valid
      expect(new_invite.errors[:invitee].first).to include("has already accepted")
    end

    it 'allows invitation to non-member' do
      allow_any_instance_of(ChatInvitation).to receive(:send_notification)

      invitation = ChatInvitation.new(
        chat: chat,
        inviter: inviter,
        invitee: invitee
      )
      expect(invitation).to be_valid
    end
  end

  describe '#accept!' do
    let!(:invitation) do
      allow_any_instance_of(ChatInvitation).to receive(:send_notification)
      ChatInvitation.create!(
        chat: chat,
        inviter: inviter,
        invitee: invitee,
        status: :pending
      )
    end

    it 'creates a ChatMember for the invitee' do
      expect { invitation.accept! }.to change { chat.chat_members.count }.by(1)

      new_member = chat.chat_members.find_by(member: invitee)
      expect(new_member).to be_present
      expect(new_member.role).to eq('member')
    end

    it 'updates status to accepted with responded_at' do
      invitation.accept!
      invitation.reload

      expect(invitation).to be_status_accepted
      expect(invitation.responded_at).to be_present
    end

    it 'creates a system message announcing the join' do
      expect { invitation.accept! }.to change { chat.messages.count }.by(1)

      system_msg = chat.messages.last
      expect(system_msg.content).to include(invitee.user.name)
      expect(system_msg.content).to include("joined the chat")
      expect(system_msg.role).to eq('assistant')
      expect(system_msg.metadata['system_event']).to eq('member_joined')
    end

    it 'performs all operations atomically' do
      # Force a failure mid-transaction by making message creation fail
      allow(chat.messages).to receive(:create!).and_raise(ActiveRecord::RecordInvalid)

      result = invitation.accept!

      expect(result).to be false
      invitation.reload
      expect(invitation).to be_status_pending
      expect(chat.chat_members.exists?(member: invitee)).to be false
    end
  end

  describe '#ignore!' do
    let!(:invitation) do
      allow_any_instance_of(ChatInvitation).to receive(:send_notification)
      ChatInvitation.create!(
        chat: chat,
        inviter: inviter,
        invitee: invitee,
        status: :pending
      )
    end

    it 'updates status to ignored with responded_at' do
      invitation.ignore!
      invitation.reload

      expect(invitation).to be_status_ignored
      expect(invitation.responded_at).to be_present
    end

    it 'does not create a ChatMember' do
      expect { invitation.ignore! }.not_to change { chat.chat_members.count }
    end
  end

  describe 'notification on create' do
    it 'sends a ChatInvitationNotifier to the invitee' do
      notifier_double = instance_double(ChatInvitationNotifier)
      allow(ChatInvitationNotifier).to receive(:with).and_return(notifier_double)
      allow(notifier_double).to receive(:deliver)

      ChatInvitation.create!(
        chat: chat,
        inviter: inviter,
        invitee: invitee,
        status: :pending
      )

      expect(ChatInvitationNotifier).to have_received(:with).with(
        hash_including(
          chat_name: chat.name,
          inviter_name: inviter.user.name
        )
      )
      expect(notifier_double).to have_received(:deliver).with(invitee.user)
    end
  end
end
