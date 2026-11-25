# Ruby on Vibes Starter

An opinionated Rails starter for applications with agents working on business
records. It combines workspaces, authentication, chat, human decisions, files
and durable background execution using native Rails and RubyLLM capabilities.

Built on Ruby **4.0.10**, Rails **8.1.4.1**, RubyLLM **2.2.3**, Falcon, Solid Queue
and Solid Cable, with ERB/Turbo, React islands and Inertia pages.

## Quickstart

```sh
git clone <your-fork-url>
cd <your-app>
cp .env.example .env
# Add ANTHROPIC_API_KEY or OPENAI_API_KEY to .env.
bin/setup --skip-server
bin/dev
```

Open http://localhost:3000. `bin/dev` starts the web process, durable workers and
asset watchers. Provider credentials enable local chat without a platform
account. Keep hosted-platform variables unset for normal local development.

Set `LLM_MODEL` to override the default model and configure that provider's key.
Use an uncommitted `.env` or deployment environment variables for credentials.
`LLMS_ENABLED=true` only exposes the feature; it does not supply credentials.
`LLMS_ENABLED=false` disables the default chat gate; `AGENTS_ENABLED=true`
separately enables persistent automation. These visibility settings do not block
direct RubyLLM calls from application code. Restart after changing them.

## What the starter supplies

- **Durable conversations:** `ChatRun` stores the initiating actor and dispatch
  intent. Solid Queue delivers work; RubyLLM owns claims, persisted messages,
  questions and deferred tool tasks. Solid Cable carries worker updates.
- **Named purposes:** application-owned names select trusted native agent classes
  with purpose-specific tools, instructions and schemas.
- **Human decisions:** authenticated approval and question UI, with original actor
  authorization checked again when execution resumes.
- **Files and artifacts:** native file stores backed by Active Storage, with
  chat-scoped upload/list/download authorization.
- **Trigger delivery:** scheduled slots and webhook receipts are deduplicated and
  wait durably for the conversation to become available.
- **Usage ownership:** calls inside the chat job belong to its run. Other services
  establish their own owner through `RubyLLM.with_owner`.
- **Application basics:** users, workspaces, roles, notifications and optional
  billing, administration and analytics.

Slow tools use **one native task protocol**. Ordinary Rails jobs perform the
work; domain records hold business progress and evidence. The old application
task runner and its polling UI have been removed. See the opt-in
[native task recipe](docs/native-task-recipe.md) for an approval-gated report
publication with a unique business key, immutable input and worker resumption.

Delivery is at least once. Native execution does not make external business
side effects exactly once. Tools still need authorization, business idempotency
and reconciliation appropriate to the operation. Stored file contents are
mutable unless the application preserves immutable approved evidence.

## Start building

1. Read [agent foundations](docs/agent-foundations.md) for execution ownership and
   its limits.
2. Add an `ApplicationAgent` and register a [named purpose](docs/chat_purposes.md).
   Declare tools on that purpose; no central job edits are needed.
3. Follow [building with agents](docs/building_with_agents.md) for schemas, tools,
   decisions, provider-free tests and explicit quality evaluations.
4. Use [chat files](docs/chat-files.md) and [trigger delivery](docs/webhooks.md)
   when the feature requires uploads or automation.

RubyLLM already includes MCP, skills, evaluations and instrumentation. Configure
those capabilities deliberately when needed; do not add a parallel framework
for native functionality. Anthropic and OpenAI keys are configured by default.
Other providers require explicit configuration and integration checks.

## Validation

```sh
bundle exec rspec
bin/rails zeitwerk:check
bundle exec ruby script/check_durable_execution.rb
bundle exec ruby script/check_shared_broadcasts.rb
```

The default tests use scripted providers and exercise the real conversation
loop. Process probes use disposable SQLite databases. Live model quality,
production PostgreSQL concurrency and deployment compatibility require separate
checks. [Release exercises](docs/llm_release_exercises.md) describe opt-in live
checks; they are not part of the default test run.

## Application guides

- [Workspaces and members](docs/workspaces.md)
- [Record context](docs/contexts.md) and [mentions](docs/mentionable.md)
- [Notifications](docs/notifications.md)
- [Shared broadcasts](docs/shared_broadcasts.md), [queues](docs/queue.md) and [cache](docs/cache.md)
- [JavaScript](docs/javascript.md), [Tailwind](docs/Tailwind.md) and [SSR](docs/ssr.md)
- [Deployment guides](docs/deployment/)
- [RubyLLM migration history](docs/rubyllm-upgrade.md)

```text
app/agents/       Native agent declarations and named application behavior
app/tools/        RubyLLM tools with application authorization
app/jobs/         Ordinary Rails jobs and durable conversation delivery
app/models/       Application records, ChatRun, AgentDelivery and domain operations
app/services/     Default assistant tool selection and application services
app/javascript/   Shared React components and UI adapters
```

## Optional modules and deployment

Billing, Madmin administration, Blazer/Ahoy analytics, Mailbin and development
MCP introspection can be disabled or removed when unnecessary. Billing is
configured in `config/vibes.yml`. Tidewave requires `TIDEWAVE_ENABLED=true` and a
shared secret. Mailbin is enabled in development; production requires explicit
configuration when no real mailer is present.

The repository includes a production Dockerfile, Render Blueprint examples,
Kamal configuration and a Fly configuration. Configure an application's own
environment and target account before deployment; these files are starting
points, not proof of a validated deployment.

The optional hosted-platform code-sync endpoints are off by default. They mount
only with `VIBES_API_ENABLED=true` and require `VIBES_API_TOKEN`. Leave both unset
for ordinary standalone use. See [Vibes API](docs/vibes-api.md).

## Maintaining the starter

`main` is the official starter. Product demos stay on separate branches; the
document-intake demo is on `codex/document-intake-demo`.

The standalone repository is canonical for the platform's embedded
`spec/templates/0_1_0/`. In the platform checkout,
`script/sync-from-public-template` previews differences, `--apply` copies a clean
committed starter `main`, and `--check` verifies parity after review and commit.
The sync command never commits, pushes or deploys. Source parity does not certify
platform runtime compatibility.

The starter targets new applications. Its fresh schema includes native RubyLLM
task persistence and application delivery records; the prototype task storage
and APIs are absent.

## Community and license

[Website](https://rubyonvibes.com) · [Discord](https://discord.gg/DrfUKhtFmD)

MIT — see [LICENSE](LICENSE).
