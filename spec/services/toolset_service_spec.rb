# frozen_string_literal: true

require "rails_helper"

RSpec.describe ToolsetService do
  let(:member) { members(:alice_personal_member) }
  let(:chat) { chats(:alice_personal_chat) }

  def service
    described_class.new(chat: chat, sender_user: member.user,
      sender_member: member, sender_workspace: member.workspace)
  end

  it "does not add default or task tools to an explicitly empty agent selection" do
    agent = Agent.create!(chat: chat, member: member, workspace: member.workspace,
      name: "Restricted", identifier: "restricted", tool_config: [])
    chat.reload

    expect(service.tool_classes).to be_empty
    expect(agent.configured_tool_classes).to be_empty
  end

  it "does not instantiate arbitrary constants stored in legacy records" do
    agent = Agent.create!(chat: chat, member: member, workspace: member.workspace,
      name: "Restricted", identifier: "restricted")
    agent.update_column(:tool_config, [ "File" ])
    chat.reload

    expect { service.tools }.to raise_error(ToolsetService::InvalidToolConfiguration)
  end

  it "allows an application to register an optional tool without adding it to defaults" do
    custom_tool = Class.new(RubyLLM::Tool) do
      description "An application-specific operation"
      def execute = "Done"
    end
    stub_const("OptionalApplicationTool", custom_tool)
    allow(described_class).to receive(:additional_tool_classes).and_return([ OptionalApplicationTool ])

    expect(described_class.resolve([ "OptionalApplicationTool" ])).to eq([ OptionalApplicationTool ])
    expect(service.tool_classes).not_to include(OptionalApplicationTool)
  end

  it "rejects disabled debug tools even when a persisted agent names one" do
    allow(RubyOnVibes).to receive(:debug_tools?).and_return(false)

    expect { described_class.resolve([ "Examples::RenameChatTool" ]) }
      .to raise_error(ToolsetService::InvalidToolConfiguration)
  end

  it "offers the approval reference tool when explicitly enabled" do
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
