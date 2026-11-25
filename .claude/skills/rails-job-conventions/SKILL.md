---
name: rails-job-conventions
description: Use when creating or modifying Rails jobs in app/jobs
---

# Rails job conventions

Durable application and agent work uses Solid Queue through ApplicationJob. Run `bin/jobs` alongside the web process. Falcon handles HTTP/WebSockets; Solid Cable carries worker broadcasts across processes. Do not pin agent execution or Turbo broadcast jobs to an in-process async adapter.

Pass record IDs. Persist dispatch intent before enqueueing; missing deliveries and expired native claims are recovered by ResumeChatRunsJob. ChatStreamJob accepts a ChatRun ID and rebuilds its purpose and original actor from saved records. Native RubyLLM owns conversation claims, tool/task state and message persistence. Never delete or hide tool results to repair interruption or cancellation.

Use native RubyLLM::Task for resumable tool work, Tool#resume for idempotent progress checks, and native questions/approvals for human decisions. Waiting cannot depend on an open browser. Do not hold a database transaction across provider or external network calls.

Delivery may repeat. A terminal-state check alone is not a concurrency guard. Protect business effects with unique operation keys, transactions and external API idempotency where supported. Distinguish a tracking/progress record from the operation that performs the effect. Explicitly define retryable errors and their bounds.

Keep jobs small; authorization and business rules belong in models/services. Recheck the initiating actor's current access on resume. Do not substitute the approver or the current browser user for the saved actor.

See docs/agent-foundations.md and docs/shared_broadcasts.md for the application contracts and validation commands.
