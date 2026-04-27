# Webhooks

Persistent agents can receive external events via webhooks. Any service that can send an HTTP POST (GitHub, Stripe, Linear, custom scripts) can trigger an agent run.

## How it works

Each agent has a unique **webhook token** generated automatically on creation. The token is the auth — no API keys or sessions needed.

```
POST /api/v1/hooks/:token
```

When a webhook arrives:

1. The payload is posted as a message in the agent's chat
2. An `AgentTask` is created with `trigger: "webhook"`
3. A `ChatStreamJob` fires so the agent can reason about the event
4. The endpoint returns `202 Accepted` with the task ID immediately

## Finding the webhook URL

```ruby
agent = Agent.find_by(identifier: "manager")
agent.webhook_url
# => "https://your-app.fly.dev/api/v1/hooks/a1b2c3d4..."
```

Or from the agents admin UI (when available).

## Testing with curl

```bash
curl -X POST https://your-app.fly.dev/api/v1/hooks/YOUR_TOKEN \
  -H "Content-Type: application/json" \
  -H "X-Event-Type: test" \
  -d '{"message": "Hello from curl"}'
```

Response:
```json
{"task_id": "agent_task_abc123"}
```

The agent will see:
> Webhook received: test
> ```json
> {"message": "Hello from curl"}
> ```

## GitHub example

1. Go to your GitHub repo → **Settings** → **Webhooks** → **Add webhook**
2. Set **Payload URL** to your agent's `webhook_url`
3. Set **Content type** to `application/json`
4. Select events (e.g., "Push events", "Pull request events")
5. Click **Add webhook**

The agent will receive a message each time the selected events fire. GitHub sends an `X-GitHub-Event` header that the endpoint uses automatically as the event label.

## Regenerating tokens

If a token is compromised:

```ruby
agent.regenerate_webhook_token!
```

This invalidates the old URL immediately. Update the webhook URL in any external services.

## Event headers

The endpoint looks for event type in these headers (in order):

1. `X-Event-Type` (generic, use for custom integrations)
2. `X-GitHub-Event` (GitHub-specific)
3. Falls back to "external event" if neither is present

## Payload handling

- Message content: first 2,000 characters of the raw payload
- Task metadata: full JSON (parsed) or first 5,000 characters (if not valid JSON)
- Both JSON and plain text payloads are accepted

## Adding signature verification

The generic endpoint uses token-based auth (the URL itself is the secret). For additional security with a specific service, create a controller that verifies signatures before forwarding:

```ruby
# app/controllers/api/v1/github_webhooks_controller.rb
module Api
  module V1
    class GithubWebhooksController < Api::V1::BaseController
      skip_before_action :setup_current

      def receive
        verify_signature!

        # Forward to the generic webhook handler
        agent = Agent.find_by!(webhook_token: params[:token])
        # ... same logic as WebhooksController#receive
      end

      private

      def verify_signature!
        signature = request.headers["X-Hub-Signature-256"]
        payload = request.body.read
        expected = "sha256=" + OpenSSL::HMAC.hexdigest("SHA256", ENV["GITHUB_WEBHOOK_SECRET"], payload)

        unless ActiveSupport::SecurityUtils.secure_compare(signature.to_s, expected)
          head :unauthorized
        end

        request.body.rewind
      end
    end
  end
end
```

## Rate limiting

For production, consider adding rate limiting with `rack-attack`:

```ruby
# config/initializers/rack_attack.rb
Rack::Attack.throttle("webhook/ip", limit: 60, period: 60) do |req|
  req.ip if req.path.start_with?("/api/v1/hooks/")
end
```
