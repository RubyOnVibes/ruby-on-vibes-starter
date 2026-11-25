# Template maintenance review — November 25, 2026

## Decision and scope

The objective is a secure, reproducible Rails foundation that composes native
RubyLLM primitives with application-owned authorization and lifecycle tracking.
Use the framework's conversation loop, questions, claims and accounting rather
than create another agent framework. Keep features requiring application policy
opt-in, and distinguish an available library API from a complete product feature.

This review covers both `ruby-on-vibes-starter` and the platform's embedded
`spec/templates/0_1_0`. Their shared implementation and dependencies are aligned.
The platform application's own dependencies, database and deployment integrations
are separate. Platform validation is deferred to the owner's other computer.
No Fly CLI commands, deployment, push, or external provider calls are part of this
work. Existing uncommitted changes were preserved.

The original prompt's September baseline was stale: the standalone checkout
already contained November work for RubyLLM 2.2, including typed questions,
native execution claims and usage ownership. These were retained and checked.

## Verified versions

| Component | Standalone before | Embedded before | Both after |
| --- | --- | --- | --- |
| Ruby | 4.0.9 | 4.0.7 | 4.0.10 |
| Rails | 8.1.4 | 8.1.4 | 8.1.4.1 |
| RubyLLM | 2.2.0 | 2.0.0 | 2.2.3 |

[Ruby 4.0.10](https://www.ruby-lang.org/en/news/2026/11/18/ruby-4-0-10-released/)
addresses the November Regexp/String vulnerabilities.
[Rails 8.1.4.1](https://rubyonrails.org/2026/11/4/Rails-8.0.5.2-and-8.1.4.1-have-been-released)
is the current stable security patch.
[RubyLLM 2.2.3](https://github.com/crmne/ruby_llm/releases/tag/v2.2.3)
is the current stable gem. The 2.2 patch updates require no new schema migration;
the embedded 2.0 copy needs the existing ordered cleanup, 2.1 and 2.2 migrations.

The security scan also required targeted lockfile updates:

| Dependency | Before | After |
| --- | --- | --- |
| addressable | 2.9.0 | 2.9.2 |
| crass | 1.0.7 | 1.0.8 |
| msgpack | 1.8.5 | 1.8.7 |
| net-ssh | 7.3.0 | 7.3.10 |
| rack | 3.2.7 | 3.2.9 |
| sqlite3 | 2.9.6 | 2.10.2 |
| rails-html-sanitizer | 1.7.1 | 1.7.2 |
| loofah | 2.25.2 | 2.25.3 |
| nokogiri | 1.19.4 | 1.19.7 |

The last three also follow Rails' sanitizer requirements. Node and JavaScript
dependency locks did not need changing. Ruby is pinned consistently in
`.ruby-version`, Docker and deployment examples; CI already reads `.ruby-version`.

## Small integrations implemented

- Share native tool limits between `ApplicationAgent` and `ChatStreamJob`:
  25 tool rounds per completion, 50 tool calls per model response. Excess calls
  do not execute. Reaching the round limit preserves results/accounting and
  creates a separate assistant notice. It does not automatically retry.
- Disable RubyLLM request/response body logging. This does not sanitize other
  application loggers or tool code.
- Display question choice titles without changing submitted values. This works
  for hash choices and typed multi-select answers through the existing serializer.
- Make `PORT=... bin/dev` reliable using a separate `WEB_PORT`, because Foreman
  changes `PORT` for each process. Web and background URL helpers share it.
- Make old schema-loaded databases eligible for cleanup only when their removable
  legacy columns contain no data. Unverified legacy values still stop cleanup.
- Repair historical migration replay: correct a filename/class mismatch,
  preserve the original user-reference chronology, use portable metadata storage,
  and make old rename steps accept an already-renamed schema.

Round limits reset for a new completion, including approval/question resumes.
They are not a total-run or monetary budget. Parallel tools remain opt-in.

## RubyLLM changes since 2.2.0

| Capability | Coverage after this update |
| --- | --- |
| Integer per-response tool-call cap (2.2.1) | Covered in both standard entry points. |
| Native question choice titles (2.2.2) | Covered by existing serialization and updated React UI. |
| Hash shorthand for titled choices (2.2.3) | Covered; raw values are preserved. |
| Bound parallel tool workers (2.2.3) | Available, not enabled. Set `concurrency` and `workers` deliberately for thread/fiber-safe tools. |
| Override model prices (2.2.3) | Partial: native ledger supports overrides, but the app must configure its negotiated/custom prices. |
| Wrap claim renewal for PostgreSQL RLS (2.2.3) | Available; unnecessary for current application-policy tenancy. Required if an app adopts database RLS. |
| Gemini judgments (2.2.3) | Available; no template quality-evaluation workflow configured. |
| Rerank through OpenAI-compatible endpoints (2.2.3) | Available; no retrieval pipeline configured. |
| Suppress request/response bodies in logs (2.2.3) | Covered; explicit default off. Upstream also filters API keys. |

Relevant fixes retained by the upgrade: successful tools survive a later tool
failure; PostgreSQL message saving avoids an extra locking write; queued messages
survive claim races; cancellation releases claims under fiber connection pressure;
question answers are matched to the question actually replayed; non-finite numbers
and invalid list values are rejected; folder stores reject symlink traversal and
avoid stale converted text; model refresh preserves referenced registry rows;
ordinary Ruby classes under `app/skills` remain autoloadable. Usage from a failed
judgment is recorded before parsing, and code-execution file descriptions stay
stable across later runs.

Sources: [2.2.1](https://github.com/crmne/ruby_llm/releases/tag/v2.2.1),
[2.2.2](https://github.com/crmne/ruby_llm/releases/tag/v2.2.2),
[2.2.3](https://github.com/crmne/ruby_llm/releases/tag/v2.2.3).
MiniMax structured output remains unsupported after retirement of its supporting
model; upgrading the library does not make every provider support every feature.

## Wider primitive inventory

| Primitive | Template coverage |
| --- | --- |
| Persisted chats/messages | Covered with `acts_as_chat`, `acts_as_message`, native supporting tables and workspace policies. |
| Reusable native agents | Partial: `ApplicationAgent` is a base class; the built-in UI job does not bind a selected native agent class. |
| Persistent workspace agents | Partial: identity, instructions, tools, webhook entry and schedule fields exist. Schedule fields alone do not install recurring jobs. |
| Approvals, typed questions, URL acknowledgements | Covered with authorization, persisted decisions, resume and audit metadata. |
| Native deferred tasks/subagents | Not integrated with `ChatRun`: its completion logic handles application `AgentTask`, not native `pending_tasks`. |
| Claims and interrupted recovery | Partial: duplicate/busy claims and explicit resumes are handled; no automatic interrupted-chat sweep. |
| Native queued/steered messages | Partial: app retries busy claims but does not expose the full native queue/steering API. |
| Streaming and cancellation | Covered for conversation text and tools; rich citations/thinking/media do not all have dedicated UI. |
| Usage/cost | Covered within the chat job via native ownership and `ChatRun` snapshots. Other calls require explicit ownership. |
| Context and model resilience | Context budget and compaction configured; prompt caching/fallbacks opt-in; finite tool loops configured. |
| Structured output | Native schemas and examples available; no universal task-specific chat profile yet. |
| Provider-free tests/evaluations | Native test helper used; quality evaluations are explicitly invoked and app-specific. |
| MCP/OAuth, skills, file stores | Native APIs/schema available; no automatic server, credential, file-store or skill policy. |
| Code execution/escalation | Not enabled. Requires `mxc`, sandbox policy and application approval integration. |
| Hosted tools, media, batches, judgments, reranking | Native APIs available, no turnkey product flows. |
| Tool wrappers, exclusive tools, halt/rescue hooks | Available for app code; no common application policy configured. |
| Tracing/OpenTelemetry and transport controls | Native integration points; no installed exporter or custom transport policy. |

See [native agents](https://rubyllm.com/agents/) and
[durable agents](https://rubyllm.com/durable-agents-overview/). Library primitives
do not replace workspace authorization, business idempotency or delivery policy.

## Three proposed additions (not implemented)

1. **Named chat purposes backed by native agents — medium, 8–12 files.**
   Persist an allowlisted purpose key on `Chat`, then bind the corresponding
   `ApplicationAgent` subclass on every turn/resume. Keep models, schema, tools,
   MCP and skills in the native DSL; keep authorization/usage in `ChatRun`.
   Files: agent base/purpose classes, new purpose registry, `chat.rb`, `agent.rb`,
   `chat_stream_job.rb`, `toolset_service.rb`, migration, integration specs.
   This supports reusable assistants and narrow extraction/review chats without
   two competing configuration systems. Distinguish `nil` tools (defaults) from
   `[]` (no tools); the current persisted agent treats both as defaults.

2. **Durable run dispatch and reconciliation — medium/large, 10–15 files.**
   Build on SolidQueue plus native claims, retain actor/run identity, recover
   interrupted chats, and reconcile native waiting tasks and automation outcomes.
   Files: dispatcher/recovery jobs, `ChatStreamJob`, `ChatRun`, `AgentTask`,
   scheduled/webhook jobs, recurring configuration, migrations and lifecycle specs.
   Existing async jobs can disappear with their process. Automation tracking
   tasks are not currently finalized by chat completion; native waiting tasks
   may be mistaken for a finished run. Dynamic schedules need polling/deduplication,
   or explicit recurring configuration instead of implying automatic scheduling.

3. **Optional files and external capabilities per purpose — medium, 8–12 files.**
   Configure per-chat Active Storage file stores and allowlisted MCP/skills in
   the same purpose setup path. Files: capability configuration/service, purpose
   classes, chat setup, message/artifact rendering, encryption configuration,
   docs and integration specs. This makes capabilities survive fresh jobs and
   human-decision resumes with clear credential ownership. Leave sandbox
   execution disabled until filesystem/network permissions are explicitly defined.

## Documentation awaiting public-claim review

README public claims were left unchanged. Recommended wording/corrections:

- Replace the absolute nonblocking claim with: “Scheduler-compatible I/O yields;
  CPU-heavy work and blocking libraries need a separate worker.”
- Replace universal accounting language with: “Calls inside `ChatStreamJob` are
  attributed to its `ChatRun`; other services and automation setup must establish
  ownership explicitly.” Scheduled/webhook pre-run compaction is outside the run.
- Explain that recurring configuration invokes scheduled agents; a stored schedule
  does not install a recurring task. Remove the unqualified idempotency comment
  for scheduled delivery until it has a delivery/slot dedupe key.
- Quickstart should show `bin/setup --skip-server` before a separate `bin/dev`.
  Port 3000 is now the implemented default.
- Embedded README's older RubyLLM wording should be reconciled with the updated
  starter after reviewing its broader public claims.
- CHANGELOG still describes the initial release, names SolidCable despite async
  cable configuration, and implies preconfigured Google/Ollama support. The
  initializer configures Anthropic/OpenAI; other providers need explicit setup.
  Add an unreleased maintenance entry after agreeing on the public feature claims.

## Validation and migration limits

| Check | Result |
| --- | --- |
| Standalone baseline | 478 examples, 0 failures on Ruby 4.0.9 / Rails 8.1.4 / RubyLLM 2.2.0. |
| Embedded baseline | 455 examples, 0 failures on its original dependencies, using installed Ruby 4.0.9; configured 4.0.7 was not installed locally. |
| Upgraded standalone | 501 examples, 0 failures. |
| Upgraded embedded | 501 examples, 0 failures. |
| Dependency audit | No known vulnerabilities against ruby-advisory-db commit `c87703e7f2c64f8745ce032711308a17d10cda55` (updated November 22). |
| Dev stack before/after | All six processes started; Falcon `/up` and `/` returned HTTP 200. Custom `PORT=4311` worked after the Foreman fix. Processes were stopped afterward. |
| Autoload and frontend | Zeitwerk passed; production Vite/islands and SSR builds passed; titled choices rendered with unchanged option values. |
| Populated 2.0 schema upgrade | Four messages, a tool-result link and usage row retained all shared fields exactly, including timestamps and cost. |
| Full history from empty | All 88 migrations completed through 2.2; 46 tables, no foreign-key violations. Semantic schema comparison found only the pre-existing invitation-index difference below. |
| Cleanup guard | 18 isolated subprocess examples preserve native data and reject every unverified legacy field before schema changes. |

Initial test failures exposed an error notice overwriting a successful tool
result and older orchestration test doubles missing the new options call. Both
were fixed; the regression tests use the native conversation loop. Concurrent
test attempts initially locked the same SQLite database; final suites used
separate databases. Ruby native extensions were installed for the matching Ruby
interpreter after rejecting reuse of extensions linked to another installation.

The fresh-history check must remove the disposable schema dump: Rails 8.1
`db:migrate` can initialize a blank database from it and otherwise bypass history.
One unrelated historical schema difference remains: replay creates a unique
invitation index for pending/accepted statuses, while the existing dump limits
it to pending invitations. The model validates both statuses. Normalizing that
index for existing databases needs a separate duplicate-data review.

Run `bundle install`, then `bin/rails db:migrate` with a backed-up database when
upgrading an existing installation. RubyLLM cleanup is intentionally irreversible;
use a backup/forward recovery, not an assumed rollback. Customized PostgreSQL
schemas, especially legacy cost fields, need their own populated-data rehearsal.
Local verification uses disposable SQLite databases and dummy provider credentials.
It does not certify real provider behavior, production PostgreSQL or platform/Fly
deployment compatibility. A production Docker image was not built in this review.
