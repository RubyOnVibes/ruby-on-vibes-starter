require "rails_helper"
RSpec.describe "Submitting durable chat turns", type: :request do
  let(:chat) { chats(:alice_personal_chat) }
  before do
    sign_in users(:alice)
    patch start_session_workspace_path(workspaces(:alice_personal))
    chat.chat_runs.active.delete_all
    allow(ChatStreamJob).to receive(:perform_later)
  end

  [:running, :awaiting_approval, :awaiting_tasks].each do |state|
    it "preserves a #{state} turn when another message is submitted" do
      run = chat.chat_runs.create!(status: state, initiated_by_member: members(:alice_personal_member))
      expect { post "/chats/#{chat.to_param}/messages", params: { content: "New request" }, as: :json }.not_to change(Message, :count)
      expect(response).to have_http_status(:conflict)
      expect(run.reload.status).to eq(state.to_s)
      expect(ChatStreamJob).not_to have_received(:perform_later)
    end
  end

  it "persists dispatch intent and sender before enqueueing" do
    post "/chats/#{chat.to_param}/messages", params: { content: "New request" }, as: :json
    expect(response).to have_http_status(:ok)
    run = chat.chat_runs.order(:id).last
    expect(run.input_message.content).to eq("New request")
    expect(run.initiated_by_member).to eq(members(:alice_personal_member))
    expect(ChatStreamJob).to have_received(:perform_later).with(run.id)
  end
end
