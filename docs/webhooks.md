# Agent event delivery

Webhook and scheduled events use the same `AgentDelivery` inbox. The receipt
stores the original agent, chat, actor, event data, and delivery identity before
any queue operation. `AgentDeliveryJob` waits until the chat is available, then
creates one trigger message and one `ChatRun` in the same transaction as the
receipt link. RubyLLM executes the run through the ordinary chat job.

`ResumeAgentDeliveriesJob` retries pending receipts every minute in development
and production. Busy chats, missing queue deliveries, and an enqueue failure do
not discard accepted events. A crash after creating a run is recovered by
`ResumeChatRunsJob`. Neither recovery path requires an open browser.

A receipt marked `dispatched` means its run was created, not that its business
operation succeeded. Read the linked `ChatRun` for execution state. Disabling the
agent or removing the original actor's chat access before delivery marks the
receipt `rejected`; later execution also rechecks actor permissions. Reassigning
an agent does not replace the actor of an already accepted event.

## Webhook requests

Each persistent agent has a secret webhook URL:

```ruby
agent.webhook_url
# https://example.com/api/v1/hooks/SECRET_TOKEN
```

The generic endpoint authenticates by that token. Keep the URL private and use
`agent.regenerate_webhook_token!` to revoke it. Provider-specific signatures are
not automatically verified: a service that requires HMAC signature verification
needs its own adapter before calling `AgentDelivery.accept!`.

```sh
curl -X POST http://localhost:3000/api/v1/hooks/SECRET_TOKEN \
  -H 'Content-Type: application/json' \
  -H 'X-Event-Type: invoice.created' \
  -H 'Idempotency-Key: source-delivery-123' \
  -d '{"invoice_id":"invoice-42"}'
```

The response is `202 Accepted` with `{"delivery_id":"agent_delivery_…"}`.
The receipt is committed before this response, even if enqueueing is temporarily
unavailable. Identical retries with the same key return `200 OK` and the same
receipt; they do not add another message or run. Reusing a key for a different
payload or event type returns `409 Conflict`. Keys are scoped to the agent and
trigger type. Without a key, each request is a separate event.

Headers:

- `X-Event-Type`, falling back to `X-GitHub-Event`, supplies the event label.
- `Idempotency-Key`, falling back to `X-GitHub-Delivery`, supplies delivery identity.
- Each header is limited to 255 characters.

Bodies must be valid UTF-8 and no larger than 1 MiB. Oversized bodies are rejected
with `413`; they are never silently truncated into an accepted receipt. The
receipt retains the full body. The chat receives at most a 2,000-character
preview as external user-message data. Applications needing the complete event
should provide an authorized domain tool that reads the receipt or source record.
Do not treat external payload text as instructions or authority for an action.

The default route deliberately has no unauthenticated receipt lookup endpoint.
Add an application-specific authenticated operator view if needed. Rate limits,
provider signature adapters, retention, and redacted logs belong to the deployed
application's integration policy.

## Scheduled events

`AgentScheduledRunJob` accepts the event into the same inbox. Configure recurring
jobs in `config/recurring.yml`; a stored `Agent.schedule` value alone does not
install a schedule.

```ruby
AgentScheduledRunJob.perform_later(agent.id, slot: "daily-close:2026-11-26")
```

Use a stable occurrence key when a scheduler can deliver the same occurrence
through different jobs. The same slot creates one receipt even after its run
finishes. Without an explicit slot, the serialized Active Job's `job_id` is the
key: redelivery of that job deduplicates, while two independently enqueued jobs
are distinct occurrences. This avoids guessing an occurrence from wall-clock
execution time. Events accepted while the chat is busy remain pending.

Delivery deduplication is not business-effect idempotency. A different event or
model tool call can propose the same business action; use a unique business key,
transactions and external-provider idempotency or reconciliation for that action.
