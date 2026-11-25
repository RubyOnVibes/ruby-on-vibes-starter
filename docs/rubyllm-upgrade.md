# RubyLLM upgrades and platform compatibility

This guide applies to the standalone starter and its shared embedded template.
Both copies are aligned by the [November maintenance update](maintenance-2026-11.md).
The platform application itself has not been upgraded or deployment-tested here.

The starter and the Ruby on Vibes platform are separate Rails applications with
separate databases and dependency locks. Updating this starter does not update
the platform or applications already generated from it.

## Starter upgrade checks

Use the version in `Gemfile.lock` when reading RubyLLM documentation. This
checkout includes ordered migrations for the 2.0 cleanup, 2.1 schema, and 2.2
schema, together with the earlier migration history. The legacy SQL helper
needed by the earlier backfill is kept inside that migration so fresh database
creation does not depend on a removed gem file.

- Existing starter databases: back up first, then run `bin/rails db:migrate`
  with the matching bundle. Rehearse that path before applying it to real data.
- Fresh databases: use the normal `bin/setup` / `db:prepare` path.
- Rehearse existing-data upgrades on a disposable copy. Verify conversation
  contents, attachments, tool-result links, usage totals, and pending decisions
  before switching the application that uses the real database.
- Run the focused RubyLLM specs and the applicable exercises in
  [LLM release exercises](llm_release_exercises.md). A dependency resolution or
  schema migration alone does not verify streaming, authorization, or recovery.

For future upgrades, upstream generators cover the preceding release. Generate
and inspect each intermediate migration while that release is installed rather
than jumping directly to the final generator. See the
[2.1 guide](https://github.com/crmne/ruby_llm/blob/v2.1.1/docs/_reference/upgrading.md)
and [2.2 guide](https://rubyllm.com/upgrading/).

RubyLLM 2.2 uses `pending_questions` for approvals and other tool questions,
`decline` for refusals, and `with_owner` for usage attribution. Its persisted
chat execution claims must coexist with the starter's `ChatRun` lifecycle.
Application code should use public decision APIs instead of writing internal
approval fields. Keep authorization and business audit metadata in application
code; RubyLLM does not supply workspace policy.

Cleanup removes obsolete message columns and cannot be rolled back. Databases
created from the old schema dump have no completion markers: cleanup accepts
them only when every removable legacy column is NULL. If it finds legacy values,
it stops before changing the schema. Rehearse the backfill and finish steps on a
backup; do not manufacture a completion marker to bypass verification.

## Platform upgrade plan

The sibling platform was inspected on November 12, 2026. Its lockfile still
selects `ruby_llm 1.13.2` and the separate `ruby_llm-mcp 1.0.0`. This section is a
plan for that application, not a record of a completed upgrade.

| Stage | Work | Exit check |
| --- | --- | --- |
| Establish a baseline | Preserve existing work and make a disposable database copy. Exercise the current platform chat, Context7 tool, generation workflow, and credit ledger. | Known behavior and recorded counts/totals before migrations. |
| 1.13.2 → 1.16 | Follow the [1.x upgrade guide](https://rubyllm.com/v1/upgrading/); resolve deprecations and confirm the expected persistence schema. | Existing conversations and tools still work on 1.16. |
| 1.16 → 2.0 | Follow the [2.0 guide](https://github.com/crmne/ruby_llm/blob/v2.0.0/docs/_reference/upgrading.md). Adapt custom persistence and billing integrations; run prepare/backfill/finish, verify, then cleanup. | Historical messages, tool links, application billing data, and new usage agree. |
| 2.0 → 2.1 | Complete 2.0 cleanup before removing version-specific migration helpers. Migrate Context7 to core MCP and remove the conflicting companion gem. Run the 2.1 upgrade while 2.1 is installed. | Context7 success, timeout, and error paths work; no duplicate MCP implementation. |
| 2.1 → 2.2 | Run the 2.2 migration; adapt questions/decisions, execution claims, cancellation, and interrupted-run recovery. | Duplicate jobs, a process interruption, and resumed tools do not duplicate application actions or charges. |

The platform has several specific integration points to review:

- `app/models/chat.rb` overrides `to_llm`, `persist_new_message`, and
  `setup_persistence_callbacks`. Port the required application behavior onto
  the new persistence contract instead of retaining old framework internals.
- `app/models/message.rb` owns `tool_calls` / `tool_call` associations and adds
  billing behavior. RubyLLM 2.x owns its supporting records; migrate custom
  references and preserve application data before removing old associations.
- `app/jobs/chat_stream_job.rb` and `app/jobs/async_chat_stream_job.rb` record
  tokens and manage assistant-message persistence. Verify one visible assistant
  message, correct cancellation context, and one charge per billable event.
- `AiUsageLog`, `CreditService`, and `AiPricing` are the platform's commercial
  ledger. RubyLLM's provider-cost ledger is input to that system, not a
  replacement for credits, margins, adjustments, or idempotency.
- `app/tools/context7_tool.rb` uses the community MCP client's constructors,
  errors, result objects, and connection lifecycle. Core MCP is not a drop-in
  rename. The two packages define the same `RubyLLM::MCP` constant; do not load
  both. See the [official ecosystem notes](https://rubyllm.com/ecosystem/).
- `lib/jumpstart/app/controllers/api/v1/ai/anthropic_proxy_controller.rb`, model
  allowlists, and generated-app environment injection need compatibility checks
  with the upgraded starter. Direct provider access and mounted proxy access
  are separate cases.

## Platform Claude Agent SDK plan

The platform's separate Node worker in `script/claude` was inspected on
November 12, 2026. It pins `@anthropic-ai/claude-agent-sdk` **0.2.112**;
the npm registry and [official release](https://github.com/anthropics/claude-agent-sdk-typescript/releases/tag/v0.3.323)
both identified **0.3.323** as current. This is a read-only recommendation:
the platform SDK has not been upgraded as part of the starter work.

Preserve the worker's existing local changes and establish a working generation
baseline first. Keep the existing `query()` integration; no new agent framework
is needed. The narrow upgrade should cover:

- **Dependency and packaging:** pin the reviewed version, regenerate the lock,
  and raise the worker's Node floor from 18.0 to 18.14. The SDK now obtains its
  native CLI through optional platform packages. Keep optional dependencies
  installed and verify CLI startup on the actual runtime; an import check alone
  is insufficient. The existing Docker `npm ci --omit=dev` retains them. See the
  [quickstart](https://code.claude.com/docs/en/agent-sdk/quickstart).
- **Planning permissions:** `run.mjs` currently substitutes `acceptEdits` and
  blocks only `Edit`/`Write`, leaving shell mutations possible. Use native plan
  mode with an explicit read-only tool policy and test that reads succeed while
  edits and shell writes do not. Native plan mode supports exploration; it does
  not disable every tool. See [permissions](https://code.claude.com/docs/en/agent-sdk/permissions).
- **Terminal outcomes:** preserve SDK error results, thrown failures, timeout,
  and cancellation. The current worker can swallow an error and synthesize
  “Completed”. Report partial file changes accurately without claiming success.
- **Cancellation:** test wrapper, native CLI, and shell-child termination.
  `AdaCodeTool` currently signals the wrapper PID, and its outer timeout compares
  the current time with the current time plus the timeout, so it never expires.
- **Environment and hooks:** retain project settings/hooks and the existing
  memory configuration. Explicit SDK `env` replaces the child environment;
  retain required Git noninteractive settings and selected provider credentials.
  Verify a real project hook runs. See the
  [API reference](https://code.claude.com/docs/en/agent-sdk/typescript).
- **Streaming:** keep current block-level output for this migration. Enabling
  `includePartialMessages` alone breaks the flattened event envelope: a native
  stream event's `event` field overwrites the worker's `sdk_event` discriminator.
  Token streaming needs a separate envelope/parser change. See
  [streaming output](https://code.claude.com/docs/en/agent-sdk/streaming-output).

Add subprocess contract tests for success, errors, timeout, cancellation,
project hooks, and planning without mutations. Then exercise one disposable
generation through the platform UI. Keep this independent of the platform's
RubyLLM/database migration.

## Keeping the shared template copies aligned

The November update aligns shared source, migrations, dependency locks and built
assets in the standalone starter and embedded template. When changing either,
compare and carry the related files together, then run the template specs.
Keep local secrets, databases and dependency installation directories separate.
README public-claim differences remain recorded in the maintenance review.

The platform already reads `VIBES_LOCAL_TEMPLATE_PATH` in
`config/initializers/vibes_template.rb`. For local development, point it at this
canonical starter checkout:

```env
VIBES_LOCAL_TEMPLATE_PATH=/absolute/path/to/ruby-on-vibes-starter
```

The fallback is the platform's embedded `spec/templates/0_1_0` directory. That
copy had existing local changes when inspected; do not overwrite it as an
upgrade shortcut. First compare its application-specific changes with the
canonical starter. Generating a new app from a selected template does not
migrate an existing generated app.

Record the starter commit used for each experiment. Before changing the
platform's release template, generate a disposable app from that commit and
verify setup, sign-in, direct-key chat, tool approval, a background task, and
the platform proxy path. Keep this check separate from testing the platform's
own AI conversation.
