# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Clearing a chat during compaction", type: :request do
  it "revokes the summarizer so deleted conversation data cannot reappear" do
    user = users(:alice)
    workspace = workspaces(:alice_personal)
    member = members(:alice_personal_member)
    sign_in user
    patch start_session_workspace_path(workspace)

    chat = member.owned_chats.create!(name: "Clear during summary")
    10.times do |index|
      chat.messages.create!(role: :user, content: "Question #{index}")
      chat.messages.create!(role: :assistant, content: "Answer #{index}")
    end
    model = double
    allow(model).to receive(:ask) do
      expect(chat.reload.compaction_token).to be_present
      post clear_chat_path(chat), as: :json
      expect(response).to have_http_status(:no_content)
      expect(chat.reload.compaction_token).to be_nil
      double(content: "A summary of the deleted conversation")
    end
    allow(RubyLLM).to receive(:chat).and_return(model)

    expect(Chat::CompactionService.new(chat).force_compact!).to be false
    expect(chat.reload.compaction_summary).to be_nil
    expect(chat.last_compacted_at).to be_nil
    expect(chat.messages).to be_empty
  end
end
