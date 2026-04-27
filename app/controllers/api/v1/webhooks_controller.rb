# frozen_string_literal: true

module Api
  module V1
    ##
    # WebhooksController - Receives external events for persistent agents.
    #
    # Unauthenticated endpoint — the webhook token in the URL IS the auth.
    # External services (GitHub, Stripe, custom integrations) POST here to
    # trigger an agent run.
    #
    # POST /api/v1/hooks/:token
    #
    class WebhooksController < Api::V1::BaseController
      # No user auth — the token is the auth
      skip_before_action :setup_current

      MAX_BODY_SIZE = 1.megabyte

      # POST /api/v1/hooks/:token
      def receive
        return head :not_found unless RubyOnVibes.agents?

        agent = Agent.find_by(webhook_token: params[:token])
        return head :not_found unless agent&.active?

        chat = agent.chat

        # Deduplicate retries via Idempotency-Key header (nil = no dedup)
        idempotency_key = request.headers["Idempotency-Key"]
        if idempotency_key.present?
          existing_task = AgentTask.find_by(chat_id: chat.id, idempotency_key: idempotency_key)
          return render json: { task_id: existing_task.to_param }, status: :ok if existing_task
        end

        # Parse incoming payload (capped to prevent memory abuse)
        payload = request.raw_post.to_s.truncate(MAX_BODY_SIZE)
        event_type = request.headers["X-Event-Type"]

        # Post a trigger message in the agent's chat with webhook context
        event_label = event_type || "external event"
        chat.messages.create!(
          role: :user,
          content: "Webhook received: #{event_label}\n\n```json\n#{payload.truncate(2000)}\n```",
          user_submitted: false
        )

        # Create an AgentTask to track the webhook run
        task = AgentTask.create!(
          chat: chat,
          workspace: agent.workspace,
          member: agent.member,
          kind: "webhook_run",
          trigger: "webhook",
          idempotency_key: idempotency_key,
          metadata: {
            webhook_event: event_type,
            webhook_payload: (JSON.parse(payload) rescue payload.truncate(5000))
          }
        )

        AgentWebhookRunJob.perform_later(agent.id, task.id)

        render json: { task_id: task.to_param }, status: :accepted
      end
    end
  end
end
