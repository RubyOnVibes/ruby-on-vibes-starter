# frozen_string_literal: true

require 'rails_helper'

RSpec.describe "Webhooks", type: :request do
  let(:workspace) { workspaces(:alice_personal) }
  let(:member) { members(:alice_personal_member) }

  let(:agent) do
    chat = Chat.create!(member: member, name: "Webhook Agent Chat")
    Agent.create!(
      workspace: workspace,
      member: member,
      chat: chat,
      name: "Webhook Agent",
      identifier: "webhook_agent",
      instructions: "You handle webhooks."
    )
  end

  before do
    allow(RubyOnVibes).to receive(:agents?).and_return(true)
    allow(AgentWebhookRunJob).to receive(:perform_later)
  end

  describe "POST /api/v1/hooks/:token" do
    it 'accepts valid webhook and returns 202' do
      post "/api/v1/hooks/#{agent.webhook_token}",
        params: '{"event":"push","ref":"main"}',
        headers: { "CONTENT_TYPE" => "application/json", "X-Event-Type" => "push" }

      expect(response).to have_http_status(:accepted)
    end

    it 'creates a trigger message in the agent chat' do
      expect {
        post "/api/v1/hooks/#{agent.webhook_token}",
          params: '{"event":"push"}',
          headers: { "CONTENT_TYPE" => "application/json", "X-Event-Type" => "deployment" }
      }.to change { agent.chat.messages.count }.by(1)

      msg = agent.chat.messages.last
      expect(msg.role).to eq("user")
      expect(msg.content).to include("Webhook received: deployment")
      expect(msg.user_submitted).to be false
    end

    it 'creates an AgentTask with trigger: webhook' do
      expect {
        post "/api/v1/hooks/#{agent.webhook_token}",
          params: '{"data":"test"}',
          headers: { "CONTENT_TYPE" => "application/json" }
      }.to change { AgentTask.count }.by(1)

      task = AgentTask.last
      expect(task.kind).to eq("webhook_run")
      expect(task.trigger).to eq("webhook")
      expect(task.metadata["webhook_payload"]).to eq("data" => "test")
    end

    it 'enqueues AgentWebhookRunJob' do
      post "/api/v1/hooks/#{agent.webhook_token}",
        params: '{}',
        headers: { "CONTENT_TYPE" => "application/json" }

      expect(AgentWebhookRunJob).to have_received(:perform_later).with(agent.id, anything)
    end

    it 'returns 404 for invalid token' do
      post "/api/v1/hooks/invalid_token_here",
        params: '{}',
        headers: { "CONTENT_TYPE" => "application/json" }

      expect(response).to have_http_status(:not_found)
    end

    it 'returns 404 for inactive agent (does not leak token validity)' do
      agent.update!(active: false)

      post "/api/v1/hooks/#{agent.webhook_token}",
        params: '{}',
        headers: { "CONTENT_TYPE" => "application/json" }

      expect(response).to have_http_status(:not_found)
    end

    it 'handles non-JSON payloads gracefully' do
      post "/api/v1/hooks/#{agent.webhook_token}",
        params: "plain text payload",
        headers: { "CONTENT_TYPE" => "text/plain" }

      expect(response).to have_http_status(:accepted)

      task = AgentTask.last
      expect(task.metadata["webhook_payload"]).to include("plain text payload")
    end

    it 'uses X-Event-Type for event label' do
      post "/api/v1/hooks/#{agent.webhook_token}",
        params: '{}',
        headers: { "CONTENT_TYPE" => "application/json", "X-Event-Type" => "deploy" }

      msg = agent.chat.messages.last
      expect(msg.content).to include("Webhook received: deploy")
    end

    it 'falls back to "external event" when no event header' do
      post "/api/v1/hooks/#{agent.webhook_token}",
        params: '{"data":true}',
        headers: { "CONTENT_TYPE" => "application/json" }

      msg = agent.chat.messages.last
      expect(msg.content).to include("Webhook received: external event")
    end

    it 'truncates large payloads in message content' do
      large_payload = { data: "x" * 3000 }.to_json

      post "/api/v1/hooks/#{agent.webhook_token}",
        params: large_payload,
        headers: { "CONTENT_TYPE" => "application/json" }

      msg = agent.chat.messages.last
      expect(msg.content.length).to be < large_payload.length
    end

    it 'returns task_id in response body' do
      post "/api/v1/hooks/#{agent.webhook_token}",
        params: '{}',
        headers: { "CONTENT_TYPE" => "application/json" }

      body = JSON.parse(response.body)
      expect(body["task_id"]).to start_with("agent_task_")
    end

    context 'idempotency' do
      it 'deduplicates retries with the same Idempotency-Key' do
        headers = { "CONTENT_TYPE" => "application/json", "Idempotency-Key" => "delivery-abc-123" }

        post "/api/v1/hooks/#{agent.webhook_token}", params: '{"n":1}', headers: headers
        expect(response).to have_http_status(:accepted)
        first_task_id = JSON.parse(response.body)["task_id"]

        post "/api/v1/hooks/#{agent.webhook_token}", params: '{"n":1}', headers: headers
        expect(response).to have_http_status(:ok)
        expect(JSON.parse(response.body)["task_id"]).to eq(first_task_id)

        expect(AgentTask.where(idempotency_key: "delivery-abc-123").count).to eq(1)
      end

      it 'creates separate tasks for different idempotency keys' do
        post "/api/v1/hooks/#{agent.webhook_token}",
          params: '{}',
          headers: { "CONTENT_TYPE" => "application/json", "Idempotency-Key" => "key-1" }

        post "/api/v1/hooks/#{agent.webhook_token}",
          params: '{}',
          headers: { "CONTENT_TYPE" => "application/json", "Idempotency-Key" => "key-2" }

        expect(AgentTask.count).to eq(2)
      end

      it 'skips dedup when no Idempotency-Key header' do
        2.times do
          post "/api/v1/hooks/#{agent.webhook_token}",
            params: '{}',
            headers: { "CONTENT_TYPE" => "application/json" }
          expect(response).to have_http_status(:accepted)
        end

        expect(AgentTask.count).to eq(2)
      end
    end
  end
end
