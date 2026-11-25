# Agent foundations

The standalone starter is the primary application. It needs a Rails web process, `bin/jobs`, a database, Active Storage and configured provider credentials. No platform account or deployment CLI is required. Shared source is kept aligned with `ruby-on-vibes/spec/templates/0_1_0`; deployment integration is a separate validation task.

## Ownership

RubyLLM owns the conversation loop, claims and heartbeats, tool calls, native questions, resumable tasks, message persistence and file store. Rails owns authentication, workspace authorization, business records and durable delivery. `ChatRun` records the original actor, input message, dispatch intent, status and usage; it is not a second tool engine.

Persist a run with its input message, then call `run.dispatch!`. `ChatStreamJob` accepts the run ID, rebuilds trusted configuration, rechecks the initiating member's access and calls native `complete`. The original actor continues to execute after another participant approves. HTTP submission rejects active runs and live native claims before writing a new message.

`ResumeChatRunsJob` runs every minute in development and production. It redelivers missing dispatches, expired claims and due task polls. A working native `RubyLLM::Task` persists its data on the tool call; a later job invokes `Tool#resume`, without repeating `execute` or adding another user message. `input_required` tasks stay parked until an application callback calls `run.resume_tasks!(explicit: true)`. Native questions use the authenticated answer/approval routes. Legacy `AgentTask` progress work is supported and resumes on the server when terminal; the browser is not an execution scheduler.

Delivery is at least once. Native claims serialize the model/tool loop. A tool interrupted after starting may have partly completed; RubyLLM preserves that evidence instead of blindly replaying it. Tools that charge money, submit records or call external systems need business idempotency keys and unique indexes, plus reconciliation where necessary. `AgentTask` is a business progress record, not a universal exactly-once primitive.

Cancellation requests native cancellation and preserves all messages and tool results. Partial streaming text is transient; RubyLLM persists final messages with its claim fencing. Solid Cable carries worker updates to the web process; see [shared broadcasts](shared_broadcasts.md).

## Named purposes

`chats.purpose` defaults to `assistant`. `ChatPurpose.registry` maps stable application names to trusted `ApplicationAgent` subclasses. Add names in code, never accept arbitrary class names from requests. Each job binds the authorized persisted Chat and supplies `run_context`; the agent declares tools, instructions, schema and file behavior through native RubyLLM APIs. Purposes cannot change while work is pending.

`ChatAgent` implements the general assistant. `ChatAgentContext` contains its application-specific mentions, participant context, task progress and links. Feature agents can define a much smaller toolset without inheriting the general assistant's tools. The optional database `Agent` model describes a configurable worker identity; it is separate from a RubyLLM agent class. Its `tool_config` is a subset of the code-owned ToolsetService allowlist: nil uses defaults and an empty array grants no application tools.

Runtime instructions are rebuilt on every turn/resume without rewriting message history. Tool rounds/calls are bounded. Prompt caching and fallback models remain explicit environment opt-ins.

## Files and artifacts

See [chat files](chat-files.md). Upload/list/download access is authorized through chat membership. Native files are shared with the chat, while usage belongs to the ChatRun; do not set `chat.with_owner(run)` to implement usage accounting. That would partition file visibility by turn.

Uploads and published artifacts receive unique paths. The native file store is mutable. Versioned paths prevent accidental replacement, but applications needing immutable approved documents must retain digest/blob references and enforce immutability in their domain records.

## Design review

Claude Code and a separate Codex reviewer inspected the installed RubyLLM 2.2.3 APIs and application independently. Both recommended a small Rails delivery shell around native execution. Adopted findings: remove destructive recovery/cancellation, preserve original actor, keep shared file ownership distinct from usage ownership, use native tasks and claims, and repair browser-only continuation and tracking tasks that waited on themselves.

We did not add a generic file audit table: a starter cannot infer every product's retention and evidence policy, and a metadata log alone would not preserve overwritten content. The document-intake example on its separate branch owns its business identity and accepted output. Likewise, application AgentTask remains optional rather than becoming a parallel workflow framework.

## Validation

Run `bundle exec rspec`, `bin/rails zeitwerk:check`, and `bundle exec ruby script/check_shared_broadcasts.rb`. Tests use the real RubyLLM loop with fixture provider responses for durable pauses, approvals, cancellation and usage. The shared-broadcast probe boots two processes and a disposable database. Provider credentials are unnecessary for these checks. Real provider quality, PostgreSQL multi-host concurrency and platform deployment remain separate integration checks.
