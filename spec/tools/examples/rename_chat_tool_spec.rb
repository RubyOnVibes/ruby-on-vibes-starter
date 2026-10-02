# frozen_string_literal: true

require "rails_helper"

RSpec.describe Examples::RenameChatTool do
  let(:chat) { chats(:team_chat) }
  let(:owner) { members(:alice_team_member) }
  let(:other_member) { members(:bob_team_member) }

  it "requires human approval" do
    expect(described_class).to be_requires_approval
  end

  it "renames the chat for its owner" do
    tool = described_class.new(
      chat: chat,
      sender_user: owner.user,
      sender_member: owner,
      sender_workspace: owner.workspace
    )

    result = tool.execute(title: "Approved title")

    expect(result).to include(changed: true, title: "Approved title")
    expect(chat.reload.name).to eq("Approved title")
  end

  it "does not rename the chat for a non-owner" do
    tool = described_class.new(
      chat: chat,
      sender_user: other_member.user,
      sender_member: other_member,
      sender_workspace: other_member.workspace
    )

    expect {
      expect(tool.execute(title: "Not allowed")).to include(error: /Only the chat owner/)
    }.not_to change { chat.reload.name }
  end
end
