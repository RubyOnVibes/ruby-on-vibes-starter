# frozen_string_literal: true

require "rails_helper"
require "ruby_llm/test_helper"

RSpec.describe "Unexpected tool failures", type: :job do
  include RubyLLM::TestHelper

  let(:chat) { chats(:alice_personal_chat) }
  let(:member) { members(:alice_personal_member) }
  let(:private_detail) { "private adapter credential at /secret/config" }

  before do
    chat.chat_runs.delete_all
    chat.messages.destroy_all
    %i[broadcast_action_to broadcast_replace_to broadcast_append_to broadcast_stream_to].each do |method|
      allow(Turbo::StreamsChannel).to receive(method)
    end
  end

  def execute_failing_tool(tool_class, arguments = {})
    allow_any_instance_of(ToolsetService).to receive(:tool_classes).and_return([ tool_class ])
    input = chat.messages.create!(role: :user, content: "Use the tool", member: member, user: member.user)
    run = chat.chat_runs.create!(input_message: input, initiated_by_member: member)
    stub_replies tool_call(tool_class.tool_name.to_sym, **arguments)

    expect { ChatStreamJob.perform_now(run.id) }.to raise_error(RuntimeError, private_detail)

    expect(run.reload).to be_status_failed
    expect(chat.messages.pluck(:content).join).not_to include(private_detail)
    expect(chat.messages.where(role: :assistant).last.content).to include("could not be completed")
  end

  it "keeps unexpected web-fetch errors out of native tool results and the transcript" do
    allow(Socket).to receive(:getaddrinfo).and_raise(RuntimeError, private_detail)

    execute_failing_tool(WebFetchTool, url: "https://example.com")
  end

  it "keeps unexpected date-tool errors out of native tool results and the transcript" do
    allow_any_instance_of(User).to receive(:time_zone).and_raise(RuntimeError, private_detail)

    execute_failing_tool(CurrentDateTimeTool)
  end
end
