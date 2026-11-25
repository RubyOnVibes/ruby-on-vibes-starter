# frozen_string_literal: true

module Api
  module V1
    # The token authenticates the sender. Persist an inbox receipt before any
    # message or run is created so busy chats and queue outages cannot lose it.
    class WebhooksController < Api::V1::BaseController
      skip_before_action :setup_current

      MAX_BODY_SIZE = 1.megabyte

      def receive
        return head :not_found unless RubyOnVibes.agents?

        agent = Agent.find_by(webhook_token: params[:token])
        return head :not_found unless agent&.active?
        return head :content_too_large if request.content_length.to_i > MAX_BODY_SIZE

        payload = request.body.read(MAX_BODY_SIZE + 1).force_encoding(Encoding::UTF_8)
        return head :content_too_large if payload.bytesize > MAX_BODY_SIZE
        return head :unprocessable_content unless payload.valid_encoding?

        delivery = AgentDelivery.accept!(
          agent: agent, trigger: "webhook", payload: payload,
          event_type: request.headers["X-Event-Type"].presence || request.headers["X-GitHub-Event"].presence,
          idempotency_key: request.headers["Idempotency-Key"].presence || request.headers["X-GitHub-Delivery"].presence
        )
        accepted = delivery.previously_new_record?
        delivery.dispatch!
        render json: { delivery_id: delivery.to_param }, status: accepted ? :accepted : :ok
      rescue AgentDelivery::PayloadConflict
        render json: { error: "Delivery key was already used for another payload" }, status: :conflict
      rescue ActiveRecord::RecordInvalid
        render json: { error: "Invalid event headers or payload" }, status: :unprocessable_content
      end
    end
  end
end
