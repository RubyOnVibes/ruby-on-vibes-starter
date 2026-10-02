# frozen_string_literal: true

require "rails_helper"

RSpec.describe ToolsetService do
  let(:member) { members(:alice_personal_member) }
  let(:chat) { chats(:alice_personal_chat) }

  it "offers the approval reference tool without enabling background tasks" do
    allow(RubyOnVibes).to receive(:agent_tasks?).and_return(false)
    allow(RubyOnVibes).to receive(:debug_tools?).and_return(true)

    service = described_class.new(
      chat: chat,
      sender_user: member.user,
      sender_member: member,
      sender_workspace: member.workspace
    )

    expect(service.tool_classes).to include(Examples::RenameChatTool)
  end

  it "does not expose reference tools when debug tools are disabled" do
    allow(RubyOnVibes).to receive(:agent_tasks?).and_return(false)
    allow(RubyOnVibes).to receive(:debug_tools?).and_return(false)

    service = described_class.new(
      chat: chat,
      sender_user: member.user,
      sender_member: member,
      sender_workspace: member.workspace
    )

    expect(service.tool_classes).not_to include(Examples::RenameChatTool)
  end
end
