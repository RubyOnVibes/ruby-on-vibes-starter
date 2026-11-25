# Native task recipe: publish a prepared report

This opt-in example demonstrates a human-approved business operation that can
pause, move to a Rails worker, and resume through native RubyLLM tasks. It is
not registered in the default assistant and makes no external writes.

The application prepares an `Examples::ReportPublication` with an immutable
title, body, digest, and workspace-scoped `publication_key`. The key identifies
the business report and revision, for example `monthly-report:2026-11:revision-1`.
Choose it in application code from that business identity. A random key or a
tool-call ID cannot deduplicate the same action proposed in a later run.

## Execution ownership

1. `Examples::PublishReportTool` requires native human approval. Its only model
   argument is the prepared report's ID; the model cannot replace its contents,
   owner, or business key. Show the immutable prepared report in your application's
   review screen before asking a human to approve publication.
2. On approval, the tool rechecks the initiating actor, scopes the report to the
   authorized chat/workspace, and records the original `ChatRun` while moving the
   report to `queued` under a row lock.
3. `Examples::PublishReportJob` performs the work through ordinary Active Job.
   The tool returns `Examples::ReportPublicationTask`, a `RubyLLM::Task` whose
   saved data contains the report ID. A native task represents a paused tool call;
   it is not a job queue or a general workflow record.
4. The job locks the original run and report, rechecks current permissions and
   cancellation, then marks the report published in one short local transaction.
   A duplicate delivery or a later proposal for the same report cannot publish
   it again or change its original publication timestamp.
5. `Tool#resume` reads the persisted report. While it is queued, it can redeliver
   a missing job and returns the native task. When publication finishes, it returns
   the result. No synthetic user message or second task engine is involved.

The job deliberately performs a small local effect. For slow computation, do
the expensive work outside database locks, then reauthorize and atomically
commit the local effect. For external APIs, use the provider's business
idempotency key and reconcile unknown outcomes; this local transaction does
not make a network operation exactly once.

## Opt in

Add the existing agent class to the code-owned purpose registry when adopting
the example:

```ruby
def self.registry
  { "assistant" => ChatAgent,
    "report_publication" => Examples::ReportPublisherAgent }
end
```

Enable recovery of committed publication intent in each environment that uses
the recipe. Add this entry under `development:` and `production:` in
`config/recurring.yml` alongside the starter's existing recovery jobs:

```yaml
resume_report_publications:
  class: Examples::ResumeReportPublicationsJob
  schedule: every minute
```

This concrete business-delivery sweep is opt-in with the example. It does not
drive the conversation or replace native RubyLLM tasks.

Prepare a dedicated authorized chat and report in your application flow:

```ruby
chat = Chat.create!(member: current_member, purpose: "report_publication")
report = Examples::ReportPublication.create!(
  workspace: current_member.workspace, member: current_member, chat: chat,
  publication_key: "monthly-report:2026-11:revision-1",
  title: "November report", body: reviewed_report_text
)
```

Submitting `Publish prepared report #{report.id}` through the existing chat UI
uses the normal durable `ChatRun`, approval, native-task, and streaming path.
The original requester remains the execution actor if another authorized chat
owner confirms the operation. Applications requiring separation of duties must
add their approver policy; the starter's confirmation policy does not require a
different person.

Content and identity are immutable from creation, including while approval is
pending. Prepare a new revision for changed content. The unique database index
on workspace/business key protects against concurrent duplicate creation even
if a caller bypasses model validations.

## Cancellation and lost delivery

`ReportPublicationTask#cancel` cancels the pending business operation, and the
tool's native `task` loader reconstructs this subclass in another process.
Native cancellation is cooperative: requesting chat cancellation may persist
a flag before the native loop invokes the task hook. The application job also
checks the original run under a lock, so a cancelled run cannot later publish.
Revoked membership similarly cancels the pending operation. Cancellation never
undoes an already published report.

The paused native call polls queued work and can enqueue a missing job again.
Queue enqueue errors leave the report queued and return a native task, allowing
the next resume to redeliver it. There is also a handoff gap: the tool can die
after committing `queued` but before enqueueing the job or persisting a native
task. `ResumeReportPublicationsJob` recovers that committed intent independently
of native-task polling. It rechecks the original run and actor: active,
authorized work is redelivered; terminal runs or revoked access cancel pending
publication. Publication itself repeats those checks under the run/record locks.

This sweep never fabricates a native task or replays an interrupted tool call.
An interrupted conversation can still report that interruption; the publication
record is the evidence of whether the approved business operation occurred.
Recovery requires the configured recurring sweep and an operating worker.
Monitor stuck business deliveries and native tasks as ordinary queued work.

## Verification and evaluation

```sh
bundle exec rspec spec/tools/examples/publish_report_tool_spec.rb
```

The suite exercises the real RubyLLM conversation loop with scripted provider
responses: approval before effects, native pause/resume, duplicate worker
delivery, repeated proposals in different runs, queue failure, exit before
enqueue/native-task persistence, terminal-run reconciliation, cancellation,
membership revocation, workspace isolation, immutable inputs, and the unique
business key. It uses the run-ID-only job interface and adds no user turn on
resume.

The same suite runs a native `RubyLLM::Evaluation` with `evaluator false` over
`spec/fixtures/files/native_recipe/report_cases.json`. One prepared report
contains an instruction attack. Deterministic assertions verify that the
selected record alone is published and its source content stays unchanged.
Both the model and grader are offline: this measures execution-contract
correctness, not a real model's resistance to prompt injection, decision quality,
or token efficiency. Keep actual authorization checks as the security boundary.

For model-quality measurement, use native evaluations with reviewed held-out
documents and explicit live-call opt-in as described in
[building with agents](building_with_agents.md#evaluate-quality-explicitly).
Measure runtime inference usage separately from coding-agent build tokens and
human implementation time. No live evaluation is part of the default tests.
