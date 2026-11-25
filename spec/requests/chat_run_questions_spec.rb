# frozen_string_literal: true

require "rails_helper"

RSpec.describe "ChatRun questions", type: :request do
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

  def pending_questions!(*questions, run: nil, requester: member)
    run ||= chat.chat_runs.create!(status: :awaiting_approval, initiated_by_member: member)
    message = chat.messages.create!(role: :assistant, content: "", created_at: run.created_at + 1.second)
    call = message.ruby_llm_tool_calls.create!(
      tool_call_id: "question_call_#{message.id}",
      name: "configure_report",
      arguments: {},
      metadata: { requester_member_id: requester.id, chat_run_id: run.id },
      mcp_state: { "requests" => questions.map(&:to_h) }
    )
    ids = questions.map { |question| RubyLLM::Question.from_h(question.to_h, tool_call: call.to_llm).id }
    [run, call, ids]
  end

  def answer_question(run, id, answer)
    post "/chat_runs/#{run.id}/questions/answer", params: { question_id: id, answer: answer }, as: :json
  end

  it "persists a native question answer and resumes with the original initiator" do
    run, call, ids = pending_questions!(RubyLLM::Question.asked(0, "Window or aisle?", choices: %w[window aisle]))

    answer_question(run, ids.first, "window")

    expect(response).to have_http_status(:ok)
    expect(response.parsed_body).to include("status" => "answered", "resuming" => true, "pending_questions" => 0)
    expect(call.reload.mcp_state.dig("requests", 0, "response")).to eq(
      "action" => "accept", "content" => { "answer" => "window" }
    )
    expect(run.reload).to be_status_running
    expect(ChatStreamJob).to have_received(:perform_later).with(run.id).once
    expect(run.initiated_by_member).to eq(member)
  end

  it "persists a decline note and resumes without an answer" do
    run, call, ids = pending_questions!(RubyLLM::Question.asked(0, "Which report?"))

    post "/chat_runs/#{run.id}/questions/decline", params: { question_id: ids.first, note: "Skip this report" }, as: :json

    expect(response).to have_http_status(:ok)
    expect(call.reload.mcp_state.dig("requests", 0, "response")).to eq("action" => "decline", "note" => "Skip this report")
    expect(ChatStreamJob).to have_received(:perform_later).once
  end

  it "serializes titled choices and accepts their values rather than their labels" do
    run, call, ids = pending_questions!(RubyLLM::Question.asked(
      0, "Which account?", choices: { "17" => "River bank", "42" => "Money bank" }
    ))

    payload = JSON.parse(call.message.reload.serialize_tool_calls.to_json)
    field = payload.first.fetch("questions").first.fetch("fields").sole
    expect(field).to include(
      "choices" => %w[17 42],
      "choice_titles" => { "17" => "River bank", "42" => "Money bank" }
    )

    answer_question(run, ids.first, "River bank")
    expect(response).to have_http_status(:unprocessable_content)
    expect(call.reload.mcp_state.dig("requests", 0, "response")).to be_nil

    answer_question(run, ids.first, "17")
    expect(response).to have_http_status(:ok)
    expect(call.reload.mcp_state.dig("requests", 0, "response", "content", "answer")).to eq("17")
    expect(ChatStreamJob).to have_received(:perform_later).once
  end

  it "preserves numeric multi-choice values while serializing their titles" do
    schema = {
      "type" => "object",
      "properties" => {
        "accounts" => {
          "type" => "array",
          "items" => {
            "type" => "integer",
            "anyOf" => [
              { "const" => 17, "title" => "River bank" },
              { "const" => 42, "title" => "Money bank" }
            ]
          }
        }
      },
      "required" => ["accounts"]
    }
    run, call, ids = pending_questions!(RubyLLM::Question.asked(0, "Which accounts?", schema: schema))

    payload = JSON.parse(call.message.reload.serialize_tool_calls.to_json)
    field = payload.first.fetch("questions").first.fetch("fields").sole
    expect(field).to include(
      "type" => "array", "choices" => [17, 42],
      "choice_titles" => { "17" => "River bank", "42" => "Money bank" }
    )

    answer_question(run, ids.first, { accounts: [17, 42] })

    expect(response).to have_http_status(:ok)
    expect(call.reload.mcp_state.dig("requests", 0, "response", "content", "accounts")).to eq([17, 42])
    expect(ChatStreamJob).to have_received(:perform_later).once
  end

  it "waits for every question across tool calls before resuming once" do
    run, first_call, first_ids = pending_questions!(RubyLLM::Question.asked(0, "First choice?"))
    _, second_call, second_ids = pending_questions!(RubyLLM::Question.asked(0, "Second choice?"), run: run)

    answer_question(run, first_ids.first, "first")

    expect(response.parsed_body).to include("resuming" => false, "pending_questions" => 1)
    expect(run.reload).to be_status_awaiting_approval
    expect(ChatStreamJob).not_to have_received(:perform_later)

    answer_question(run, second_ids.first, "second")

    expect(response.parsed_body).to include("resuming" => true, "pending_questions" => 0)
    expect(first_call.reload.mcp_state.dig("requests", 0, "response", "content", "answer")).to eq("first")
    expect(second_call.reload.mcp_state.dig("requests", 0, "response", "content", "answer")).to eq("second")
    expect(ChatStreamJob).to have_received(:perform_later).once

    answer_question(run, second_ids.first, "replacement")

    expect(response).not_to have_http_status(:success)
    expect(second_call.reload.mcp_state.dig("requests", 0, "response", "content", "answer")).to eq("second")
    expect(ChatStreamJob).to have_received(:perform_later).once
  end

  it "rejects an invalid choice without settling or resuming" do
    run, call, ids = pending_questions!(RubyLLM::Question.asked(0, "Window or aisle?", choices: %w[window aisle]))

    answer_question(run, ids.first, "middle")

    expect(response).to have_http_status(:unprocessable_content)
    expect(call.reload.mcp_state.dig("requests", 0, "response")).to be_nil
    expect(run.reload).to be_status_awaiting_approval
    expect(ChatStreamJob).not_to have_received(:perform_later)
  end

  it "keeps separate answers when one tool asks multiple questions" do
    run, call, ids = pending_questions!(
      RubyLLM::Question.asked(0, "Which report?"),
      RubyLLM::Question.asked(1, "Include details?")
    )

    answer_question(run, ids.first, { answer: "Summary" })

    expect(response.parsed_body).to include("resuming" => false, "pending_questions" => 1)

    post "/chat_runs/#{run.id}/questions/decline", params: { question_id: ids.last }, as: :json

    expect(response).to have_http_status(:ok)
    expect(call.reload.mcp_state.fetch("requests").map { |question| question.fetch("response") }).to eq([
      { "action" => "accept", "content" => { "answer" => "Summary" } },
      { "action" => "decline" }
    ])
    expect(ChatStreamJob).to have_received(:perform_later).once
  end

  it "accepts a URL acknowledgement with a null answer" do
    run, call, ids = pending_questions!(RubyLLM::Question.asked(0, "Connect your account", url: "https://example.com/connect"))

    answer_question(run, ids.first, nil)

    expect(response).to have_http_status(:ok)
    expect(call.reload.mcp_state.dig("requests", 0, "response")).to eq("action" => "accept")
    expect(ChatStreamJob).to have_received(:perform_later).once
  end

  it "preserves zero, false and arrays from a structured form" do
    schema = {
      "type" => "object",
      "properties" => {
        "count" => { "type" => "integer" },
        "notify" => { "type" => "boolean" },
        "labels" => { "type" => "array", "items" => { "type" => "string" } }
      },
      "required" => %w[count notify labels]
    }
    run, call, ids = pending_questions!(RubyLLM::Question.asked(0, "Configure report", schema: schema))

    answer_question(run, ids.first, { count: 0, notify: false, labels: %w[first second] })

    expect(response).to have_http_status(:ok)
    expect(call.reload.mcp_state.dig("requests", 0, "response", "content")).to eq(
      "count" => 0, "notify" => false, "labels" => %w[first second]
    )
  end

  it "does not accept a question from a previous run on the same chat" do
    previous_run, call, ids = pending_questions!(RubyLLM::Question.asked(0, "Previous question?"))
    previous_run.update!(status: :failed)
    current_run = chat.chat_runs.create!(status: :awaiting_approval, initiated_by_member: member)

    answer_question(current_run, ids.first, "unexpected")

    expect(response).to have_http_status(:not_found)
    expect(call.reload.mcp_state.dig("requests", 0, "response")).to be_nil
    expect(ChatStreamJob).not_to have_received(:perform_later)
  end

  it "serializes settled question status without exposing the response" do
    run, call, ids = pending_questions!(RubyLLM::Question.asked(0, "What should the report say?"))

    answer_question(run, ids.first, "private response text")

    payload = call.message.reload.serialize_tool_calls.first.fetch(:questions).first
    expect(payload).to include(id: ids.first, kind: "form", status: "answered")
    expect(payload).not_to have_key(:response)
    expect(payload.to_json).not_to include("private response text")
  end

  context "when another member can access the chat but did not request the action" do
    let(:workspace) { workspaces(:team_org) }
    let(:member) { members(:alice_team_member) }
    let(:chat) { chats(:team_chat) }

    it "rejects their answer while preserving the pending question" do
      run, call, ids = pending_questions!(RubyLLM::Question.asked(0, "Which account?"))
      sign_out user
      sign_in users(:bob)
      patch start_session_workspace_path(workspace)

      answer_question(run, ids.first, "unexpected")

      expect(response).to have_http_status(:forbidden)
      expect(call.reload.mcp_state.dig("requests", 0, "response")).to be_nil
      expect(ChatStreamJob).not_to have_received(:perform_later)
    end

    it "allows that member to answer when they requested the action" do
      requester = members(:bob_team_member)
      run, call, ids = pending_questions!(RubyLLM::Question.asked(0, "Which account?"), requester: requester)
      sign_out user
      sign_in users(:bob)
      patch start_session_workspace_path(workspace)

      answer_question(run, ids.first, "Requested account")

      expect(response).to have_http_status(:ok)
      expect(call.reload.metadata.fetch("decided_by_member_id")).to eq(requester.id)
      expect(ChatStreamJob).to have_received(:perform_later).with(run.id).once
      expect(run.reload.initiated_by_member).to eq(member)
    end
  end
end
