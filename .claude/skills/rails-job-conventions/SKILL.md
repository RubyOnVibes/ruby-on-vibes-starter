---
name: rails-job-conventions
description: Use when creating or modifying Rails jobs in app/jobs
---

# Rails job conventions

Use plain `ApplicationJob` subclasses with Solid Queue. Run `bin/jobs` alongside
the web process. Falcon serves HTTP/WebSockets and Solid Cable carries worker
broadcasts. Do not bind durable work to an in-process async adapter.

Pass record IDs and persist intent before enqueueing. `ChatStreamJob.perform`
accepts one `ChatRun` ID. The run stores its original actor and input; each job
rebuilds the named purpose and rechecks current access. `ResumeChatRunsJob`
recovers missing delivery, expired native claims and due native task polls.
A duplicate delivery must leave a live native claim's owner alone.

RubyLLM owns claims, tool calls, task/question state and message persistence.
Do not introduce another orchestration base job, continuation-depth loop or
synthetic user message. Native `RubyLLM::Task` pauses a tool call; `Tool#resume`
reads the linked business operation without repeating `execute`.

Ordinary jobs perform the business work. Models own its progress, cancellation,
evidence and operation-level idempotency. Wire native task cancellation to the
application job's policy explicitly. Never hold a database transaction across a
provider or external network request. Protect short local effects with unique
business keys and transactions; external effects may require provider keys and
reconciliation after ambiguous failure.

Use Rails retry facilities for explicitly retryable errors with bounds. A
terminal-state check alone is not a concurrency guard. A new call or run may
propose the same business operation, so tool-call identity alone is insufficient.
Keep user-visible errors generic and diagnostics free of sensitive payloads.

Schedules and webhooks use the `AgentDelivery` inbox. Persist receipt identity
and payload before enqueueing, deduplicate atomically, and leave busy-chat events
pending for later delivery. Once admitted, its linked `ChatRun` owns execution.
Receipts are delivery bookkeeping, not a second conversation lifecycle.

Read `docs/agent-foundations.md`, `docs/native-task-recipe.md`, and
`docs/webhooks.md` for the tested integration paths. Recheck the initiating actor
inside the actual effect; neither a later approver nor the worker's ambient
request context may replace that actor.
