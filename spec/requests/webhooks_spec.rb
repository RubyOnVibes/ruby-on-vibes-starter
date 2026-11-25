# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Webhooks", type: :request do
  let(:member) { members(:alice_personal_member) }
  let(:agent) do
    Agent.create!(workspace: member.workspace, member: member,
      chat: Chat.create!(member: member, name: "Webhook Agent Chat"),
      name: "Webhook Agent", identifier: "webhook_agent")
  end
  let(:headers) { { "CONTENT_TYPE" => "application/json", "Idempotency-Key" => "delivery-123" } }

  before do
    allow(RubyOnVibes).to receive(:agents?).and_return(true)
    allow(AgentDeliveryJob).to receive(:perform_later)
  end

  def receive_event(body = '{"event":"push"}', event_headers = headers)
    post "/api/v1/hooks/#{agent.webhook_token}", params: body, headers: event_headers
  end

  it "accepts one durable receipt without exposing the event to a running conversation" do
    agent
    expect { receive_event }.to change(AgentDelivery, :count).by(1).and change(Message, :count).by(0)
    expect(response).to have_http_status(:accepted)
    delivery = AgentDelivery.last
    expect(JSON.parse(response.body)).to eq("delivery_id" => delivery.to_param)
    expect(delivery.payload).to eq('{"event":"push"}')
    expect(delivery.initiated_by_member).to eq(member)
    expect(AgentDeliveryJob).to have_received(:perform_later).with(delivery.id)
  end

  it "returns the same receipt for an identical retry" do
    receive_event
    first_id = response.parsed_body["delivery_id"]
    expect { receive_event }.not_to change(AgentDelivery, :count)
    expect(response).to have_http_status(:ok)
    expect(response.parsed_body["delivery_id"]).to eq(first_id)
  end

  it "rejects a delivery key reused for different data without replacing the accepted payload" do
    receive_event
    receive_event('{"event":"changed"}')
    expect(response).to have_http_status(:conflict)
    expect(AgentDelivery.count).to eq(1)
    expect(AgentDelivery.last.payload).to eq('{"event":"push"}')
  end

  it "includes the event type in delivery identity" do
    receive_event("{}", headers.merge("X-Event-Type" => "created"))
    receive_event("{}", headers.merge("X-Event-Type" => "deleted"))
    expect(response).to have_http_status(:conflict)
  end

  it "accepts plain text and Github event/delivery headers" do
    receive_event("plain text payload", { "CONTENT_TYPE" => "text/plain", "X-GitHub-Event" => "push", "X-GitHub-Delivery" => "github-1" })
    expect(response).to have_http_status(:accepted)
    expect(AgentDelivery.last).to have_attributes(payload: "plain text payload", event_type: "push", idempotency_key: "github-1")
  end

  it "accepts separate events when no idempotency key was supplied" do
    2.times { receive_event("{}", { "CONTENT_TYPE" => "application/json" }) }
    expect(AgentDelivery.count).to eq(2)
  end

  it "keeps the accepted event when queue enqueueing fails" do
    allow(AgentDeliveryJob).to receive(:perform_later).and_raise(ActiveJob::EnqueueError, "queue unavailable")
    receive_event
    expect(response).to have_http_status(:accepted)
    expect(AgentDelivery.last).to be_status_pending
  end

  it "rejects oversized bodies instead of accepting truncated data" do
    expect { receive_event("x" * (1.megabyte + 1), { "CONTENT_TYPE" => "text/plain" }) }.not_to change(AgentDelivery, :count)
    expect(response).to have_http_status(:content_too_large)
  end

  it "rejects oversized event headers" do
    receive_event("{}", headers.merge("X-Event-Type" => "x" * 256))
    expect(response).to have_http_status(:unprocessable_content)
    expect(AgentDelivery.count).to eq(0)
  end

  it "refuses invalid or disabled tokens without leaking validity" do
    post "/api/v1/hooks/invalid", params: "{}", headers: headers
    expect(response).to have_http_status(:not_found)
    agent.update!(active: false)
    receive_event
    expect(response).to have_http_status(:not_found)
  end

  it "does not accept events when persistent agents are disabled" do
    allow(RubyOnVibes).to receive(:agents?).and_return(false)
    receive_event
    expect(response).to have_http_status(:not_found)
    expect(AgentDelivery.count).to eq(0)
  end
end
