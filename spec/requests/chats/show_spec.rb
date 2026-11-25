# frozen_string_literal: true

require "rails_helper"
require "ruby_llm/test_helper"

RSpec.describe "Chat page rendering", type: :request do
  include RubyLLM::TestHelper

  let(:user) { users(:alice) }
  let(:workspace) { workspaces(:alice_personal) }
  let(:member) { members(:alice_personal_member) }
  let(:chat) { chats(:alice_personal_chat) }

  before do
    sign_in user
    patch start_session_workspace_path(workspace)
    chat.chat_runs.active.delete_all
    chat.messages.destroy_all
    allow_any_instance_of(ToolsetService).to receive(:tool_classes)
      .and_return([CurrentDateTimeTool, Examples::RenameChatTool])
  end

  it "renders the shared adapter partial for user, assistant, system, tool result and native approval messages" do
    chat.messages.create!(role: :system, content: "System instructions")
    input = chat.messages.create!(role: :user, content: "Check the date and rename this chat",
      user_submitted: true, user: user, member: member)
    run = chat.chat_runs.create!(initiated_by_member: member, input_message: input)
    stub_replies(
      tool_call(CurrentDateTimeTool.tool_name),
      tool_call(Examples::RenameChatTool.tool_name, title: "Reviewed chat")
    )
    ChatStreamJob.perform_now(run.id)
    expect(run.reload).to be_status_awaiting_approval

    get chat_path(chat)

    expect(response).to have_http_status(:ok)
    payloads = Nokogiri::HTML(response.body).css("#messages [data-message]").map do |element|
      JSON.parse(element["data-message"])
    end
    expect(payloads.map { |message| message.fetch("role") }).to include("user", "assistant", "system", "tool")
    expect(payloads.find { |message| message["id"] == input.id }.fetch("content"))
      .to eq("Check the date and rename this chat")
    tool_result = payloads.find { |message| message["role"] == "tool" }
    expect(tool_result.fetch("tool_call_name")).to eq(CurrentDateTimeTool.tool_name)
    approval = payloads.flat_map { |message| message.fetch("tool_calls") }
      .find { |call| call["name"] == Examples::RenameChatTool.tool_name }
    expect(approval).to include("requiresApproval" => true, "chatRunId" => run.id)
    expect(approval.fetch("id")).to eq(run.pending_questions.sole.tool_call.id)
  end

  it "uses the same message markup for an explicit Turbo broadcast" do
    message = chat.messages.create!(role: :assistant, content: "Ready for review")
    streams = []
    allow(Turbo::StreamsChannel).to receive(:broadcast_stream_to) do |*, content:|
      streams << content
    end

    message.broadcast_full_replace!

    document = Nokogiri::HTML.fragment(streams.join)
    expect(document.at_css("turbo-stream")["target"]).to eq("message-#{message.id}")
    payload = JSON.parse(document.at_css("[data-message]")["data-message"])
    expect(payload).to include("role" => "assistant", "content" => "Ready for review")
  end
end
