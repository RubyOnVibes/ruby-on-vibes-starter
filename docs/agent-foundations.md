# Agent foundations

The standalone starter needs a Rails web process, `bin/jobs`, a database, Active
Storage and configured provider credentials. Shared source is mirrored into
`ruby-on-vibes/spec/templates/0_1_0`; platform deployment is a separate concern.

## One execution path

RubyLLM owns the conversation loop, claims and heartbeats, tool calls, persisted
questions, native deferred tasks, messages and file store. Rails owns identity,
workspace authorization, business records and durable queue delivery. `ChatRun`
records the original actor, input message, dispatch intent, status and usage.

Persist a run with its input, then call `run.dispatch!`. `ChatStreamJob.perform`
accepts only the run ID. Each delivery rebuilds the named purpose, rechecks the
original actor's access and invokes native `complete`. Another participant's
approval does not change the acting identity. An active run or live native claim
prevents a new HTTP message from starting another turn in that conversation.

`ResumeChatRunsJob` redelivers missing dispatches, expired claims and due native
task polls. A live claim belongs to its worker; a stale duplicate delivery must
not fail or complete that worker's run. A persisted question waits for an
authorized answer. An `input_required` task waits until an application callback
calls `run.resume_tasks!(explicit: true)`.

## Deferred work

The tool protocol is `execute → RubyLLM::Task → resume → result`. Native task
data persists on its tool call. Resume reads the operation's progress and result;
it does not repeat `execute` or create a synthetic user message.

A native task is not a queue or a business-operation model. Ordinary Active Job
jobs perform background work; domain records hold progress, cancellation state
and evidence. The [native task recipe](native-task-recipe.md) demonstrates an
approved report publication with a unique business key and immutable input.
Application cancellation must be connected to the domain job explicitly.

There is no application task runner alongside this protocol. The retired
prototype task models, jobs, polling UI and continuation logic have been removed.
Schedules and webhooks use `AgentDelivery` receipts to admit a trigger once and
wait durably while a chat is busy; see [trigger delivery](webhooks.md).

Delivery is at least once. Native claims serialize conversation execution, but a
tool interrupted after starting may already have affected another system.
RubyLLM preserves that evidence rather than blindly replaying the tool. Protect
business effects with operation-level unique keys and transactions; external
services may need provider idempotency and reconciliation. A tool-call ID alone
cannot deduplicate the same business request proposed in a later run.

## Purposes and trust

`ChatPurpose.registry` maps application-owned names to `ApplicationAgent`
subclasses. The default is `assistant`. Register names in code, never resolve
request-supplied class names. Bind only a scoped chat and its initiating member.
Tools, schema, file behavior and instructions are native agent declarations;
adding a new feature does not require editing the central execution job.

The default assistant uses a small instruction policy and trusted configured
agent instructions. Mentioned records and compaction summaries enter user-role
content through `Message#to_llm`; tool results remain tool content. Neither source
material nor a model response can authorize a resource or effect. Role separation
reduces instruction confusion but does not by itself prevent prompt injection.
Recheck authorization in every business tool and asynchronous effect.

The optional database `Agent` stores workspace worker identity and configuration;
it is distinct from a native agent class. `ToolsetService` allowlists its selected
tools: nil uses assistant defaults, and an empty array grants no application
tools. A feature purpose can declare a smaller toolset directly.

## Decisions, files and usage

Native approval/question endpoints authorize decisions and record the decider.
The default permits requester confirmation or a chat-owner decision. Products
requiring a distinct approver must enforce that business policy explicitly.
Cancellation calls native cancellation and retains completed messages/results.
Solid Cable carries worker updates; partial streaming text remains transient.

File access is authorized through chat membership. The native file store belongs
to the shared chat; usage belongs to `ChatRun` through `RubyLLM.with_owner(run)`.
Changing `chat.with_owner` to attribute usage would also change file visibility.
See [chat files](chat-files.md) and [shared broadcasts](shared_broadcasts.md).

File-store contents are mutable. Unique paths reduce accidental replacement;
immutable approved evidence belongs in application records with digest/blob
references. Tool round/call limits apply per completion, not as lifetime spending
budgets. Prompt caching and fallback models remain explicit environment opt-ins.

## Validation

Run `bundle exec rspec`, `bin/rails zeitwerk:check`,
`bundle exec ruby script/check_durable_execution.rb`,
`bundle exec ruby script/check_job_delivery.rb`, and
`bundle exec ruby script/check_shared_broadcasts.rb`.

Specs use native RubyLLM execution with scripted provider responses to exercise
authorization, parked decisions, native tasks, delivery races and usage. The
process probes cover worker interruption, claim expiry, preserved results, real
Solid Queue delivery in a separate worker, harmless queued redelivery and shared
broadcasts using disposable SQLite databases. These establish execution
behavior, not model quality or production PostgreSQL concurrency. Live evaluation
and deployment qualification remain explicit, separate checks.
