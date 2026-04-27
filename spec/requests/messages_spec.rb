# frozen_string_literal: true

require 'rails_helper'

RSpec.describe "Messages", type: :request do
  let(:alice) { users(:alice) }
  let(:bob) { users(:bob) }
  let(:team_chat) { chats(:team_chat) }
  let(:team_workspace) { workspaces(:team_org) }
  let(:alice_member) { members(:alice_team_member) }

  # Set workspace in session so current_member resolves correctly
  before do
    sign_in alice
    patch start_session_workspace_path(team_workspace)
  end

  describe "POST /chats/:chat_id/messages" do
    context "when not signed in" do
      it "redirects to sign in" do
        sign_out alice
        post chat_messages_path(team_chat), params: { content: "Hello" }
        expect(response).to redirect_to(new_user_session_path)
      end
    end

    context "with empty content and no attachments" do
      it "returns 422" do
        post chat_messages_path(team_chat), params: { content: "" }, as: :json
        expect(response).to have_http_status(:unprocessable_entity)
      end

      it "returns 422 for whitespace-only content" do
        post chat_messages_path(team_chat), params: { content: "   " }, as: :json
        expect(response).to have_http_status(:unprocessable_entity)
      end
    end

    context "happy path" do
      before do
        # Stub broadcasts and job enqueue
        allow(Turbo::StreamsChannel).to receive(:broadcast_append_to)
        allow(Turbo::StreamsChannel).to receive(:broadcast_replace_to)
        allow(ChatStreamJob).to receive(:perform_later)
      end

      it "creates a message" do
        expect {
          post chat_messages_path(team_chat), params: { content: "Hello team" }, as: :json
        }.to change { team_chat.messages.count }.by(1)

        expect(response).to have_http_status(:ok)

        msg = team_chat.messages.last
        expect(msg.content).to eq("Hello team")
        expect(msg.role).to eq("user")
        expect(msg.user).to eq(alice)
        expect(msg.member).to eq(alice_member)
      end

      it "creates a ChatRun and enqueues ChatStreamJob" do
        expect {
          post chat_messages_path(team_chat), params: { content: "Hello" }, as: :json
        }.to change { team_chat.chat_runs.count }.by(1)

        run = team_chat.chat_runs.last
        expect(run).to be_status_pending

        expect(ChatStreamJob).to have_received(:perform_later).with(
          team_chat.id,
          team_chat.messages.last.id,
          run.id
        )
      end

      it "returns message data in JSON response" do
        post chat_messages_path(team_chat), params: { content: "Hello" }, as: :json

        body = response.parsed_body
        expect(body['success']).to be true
        expect(body['message_id']).to be_present
        expect(body['chat_run_id']).to be_present
      end
    end

    context "with @mentions" do
      before do
        allow(Turbo::StreamsChannel).to receive(:broadcast_append_to)
        allow(Turbo::StreamsChannel).to receive(:broadcast_replace_to)
        allow(ChatStreamJob).to receive(:perform_later)
      end

      it "substitutes mention labels with stable IDs in content" do
        other_chat = chats(:alice_personal_chat)

        post chat_messages_path(team_chat), params: {
          content: "Check out @Alice's Chat for details",
          mentions: [
            { id: other_chat.prefix_id, model: "Chat", label: "Alice's Chat" }
          ]
        }, as: :json

        expect(response).to have_http_status(:ok)

        msg = team_chat.messages.last
        expect(msg.content).to include("<@#{other_chat.prefix_id}>")
        expect(msg.content).not_to include("@Alice's Chat")
      end

      it "creates mention records for valid mentions" do
        other_chat = chats(:alice_personal_chat)

        expect {
          post chat_messages_path(team_chat), params: {
            content: "See @Alice's Chat",
            mentions: [
              { id: other_chat.prefix_id, model: "Chat", label: "Alice's Chat" }
            ]
          }, as: :json
        }.to change { Mention.count }.by(1)

        mention = Mention.last
        expect(mention.mentionable).to eq(other_chat)
      end
    end

    context "duplicate ChatRun (chat already processing)" do
      before do
        allow(Turbo::StreamsChannel).to receive(:broadcast_append_to)
        allow(Turbo::StreamsChannel).to receive(:broadcast_replace_to)
        allow(ChatStreamJob).to receive(:perform_later)
      end

      it "returns 409 conflict" do
        # Intercept only ChatRun saves (not Message saves) to simulate a
        # unique index violation. The controller creates Message first, then
        # ChatRun — this targets only the latter.
        allow_any_instance_of(ChatRun).to receive(:create_or_update) do
          raise ActiveRecord::RecordNotUnique.new("Duplicate entry")
        end

        post chat_messages_path(team_chat), params: { content: "Hello" }, as: :json
        expect(response).to have_http_status(:conflict)
      end
    end

    context "stale run cleanup" do
      before do
        allow(Turbo::StreamsChannel).to receive(:broadcast_append_to)
        allow(Turbo::StreamsChannel).to receive(:broadcast_replace_to)
        allow(ChatStreamJob).to receive(:perform_later)
      end

      it "expires stale active runs before creating new one" do
        stale_run = team_chat.chat_runs.create!(status: :running)

        post chat_messages_path(team_chat), params: { content: "Hello" }, as: :json

        expect(response).to have_http_status(:ok)
        stale_run.reload
        expect(stale_run).to be_status_failed
        expect(stale_run.failed_at).to be_present
      end
    end

    context "chat not found" do
      it "returns 404 for non-existent chat" do
        post "/chats/999999/messages", params: { content: "Hello" }, as: :json
        expect(response).to have_http_status(:not_found)
      end
    end

    context "non-member cannot send messages" do
      it "returns 404 for non-member (chat not visible)" do
        sign_in bob
        # Bob's personal workspace — alice_personal_chat is not in his chats scope
        patch start_session_workspace_path(workspaces(:bob_personal))

        # set_chat queries current_member.chats which excludes alice's chat,
        # so it hits head :not_found before Pundit — this is correct behavior
        # (doesn't leak chat existence to non-members)
        post chat_messages_path(chats(:alice_personal_chat)), params: { content: "Sneaky" }, as: :json
        expect(response).to have_http_status(:not_found)
      end
    end
  end
end
