# frozen_string_literal: true

require "rails_helper"

RSpec.describe "ChatRun tool approvals", type: :request do
  let(:user) { users(:alice) }
  let(:workspace) { workspaces(:alice_personal) }
  let(:member) { members(:alice_personal_member) }
  let(:chat) { chats(:alice_personal_chat) }

  before do
    sign_in user
    patch start_session_workspace_path(workspace)
    chat.chat_runs.active.delete_all
    allow(ChatStreamJob).to receive(:perform_later)
    allow(Turbo::StreamsChannel).to receive(:broadcast_action_to)
    allow(Turbo::StreamsChannel).to receive(:broadcast_replace_to)
  end

  def create_pending_call!(suffix: "1")
    run = chat.chat_runs.create!(status: :awaiting_approval, initiated_by_member: member)
    message = chat.messages.create!(role: :assistant, content: "", created_at: run.created_at + 1.second)
    call = message.ruby_llm_tool_calls.create!(
      tool_call_id: "approval_request_#{suffix}",
      name: "examples__rename_chat",
      arguments: { title: "New title" },
      metadata: {
        requires_approval: true,
        requester_member_id: member.id,
        chat_run_id: run.id
      }
    )
    [ run, call ]
  end

  it "approves and resumes the run" do
    run, call = create_pending_call!

    post "/chat_runs/#{run.id}/tool_approvals/#{call.tool_call_id}/approve", as: :json

    expect(response).to have_http_status(:ok)
    expect(response.parsed_body).to include("status" => "approved", "resuming" => true)
    expect(call.reload.approval).to eq("approved")
    expect(run.reload).to be_status_running
    expect(ChatStreamJob).to have_received(:perform_later).with(
      chat.id,
      nil,
      run.id,
      hash_including(
        sender_member_id: member.id,
        sender_user_id: user.id,
        approval_resume: true
      )
    )
  end

  it "denies the tool without executing it, then resumes the model" do
    run, call = create_pending_call!

    post "/chat_runs/#{run.id}/tool_approvals/#{call.tool_call_id}/deny", as: :json

    expect(response).to have_http_status(:ok)
    expect(call.reload.approval).to eq("denied")
    expect(ChatStreamJob).to have_received(:perform_later).once
  end

  it "does not accept a tool call from another chat" do
    run, = create_pending_call!

    post "/chat_runs/#{run.id}/tool_approvals/not_a_real_call/approve", as: :json

    expect(response).to have_http_status(:not_found)
    expect(ChatStreamJob).not_to have_received(:perform_later)
  end
end
