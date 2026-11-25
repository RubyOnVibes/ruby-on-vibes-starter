# Changelog

## Unreleased — Native task consolidation

- Remove the prototype application task runner, effects API, polling panel and synthetic conversation continuations. Native RubyLLM tasks are the only deferred-tool protocol.
- Keep ordinary Rails jobs and domain operation records responsible for background work, business idempotency, cancellation and evidence. Add an opt-in approval-gated report-publication recipe.
- Consolidate chat delivery around the original actor and persisted run intent; prevent stale claim retries from failing another delivery.
- Admit scheduled and webhook triggers through a deduplicated delivery inbox, including events received while a chat is busy.
- Keep untrusted mentioned-record and summary content out of application instructions; reduce the default assistant context and use generic unexpected-error responses.
- Align the guides and coding-agent conventions with native purposes, tools and task execution.
- Use Rails 8.1 application defaults for fresh applications.
- Clear the existing style-lint backlog using the repository's Rails rules.

This revision targets fresh applications. The fresh schema and migration chain omit the prototype task storage.

Validation: 480 passing specs, fresh migration replay, native worker-interruption and duplicate-delivery probes, actual Solid Queue delivery in a separate worker, shared process broadcasts, client/island/SSR builds, Zeitwerk, and clean RuboCop and dependency audits. Brakeman reports no new warnings; its one existing reviewed ignore remains. Provider replies are scripted; live model quality, PostgreSQL concurrency and platform deployment remain separate checks.

## 2026-11-25 — Durable agent foundations

- Upgrade to Ruby 4.0.10, Rails 8.1.4.1, and RubyLLM 2.2.3, with current security tooling and patched frontend dependencies.
- Run chats durably through Solid Queue, with persisted inputs, native RubyLLM claims and tasks, recovery after worker interruption, and permission-aware approval/question resumes.
- Add named chat purposes built on RubyLLM's Agent DSL and authenticated file/artifact access using its FileStore and Active Storage.
- Share worker broadcasts through Solid Cable and preserve the common chat renderer for immutable RubyLLM messages.
- Keep the document intake demonstration on its own branch; the starter contains the reusable primitives.
- Establish standalone `main` as the canonical starter and document guarded synchronization into the platform's embedded template.

Validation includes 545 passing starter specs, the matching embedded-template suite, process-level recovery checks, and a separate 560-spec document intake demo with a local browser/worker-restart exercise. Live provider behavior and platform deployment compatibility remain separate validation steps. The style-lint backlog was still open at that release snapshot; the consolidation above clears it.

The [maintenance review](docs/maintenance-2026-11.md) records that release snapshot. See [agent foundations](docs/agent-foundations.md) for the current design and its limits.

## v0.1.0 — Initial public release

First public release of the Ruby on Vibes Starter template.

- Rails 8 + Falcon + SolidQueue + SolidCache + SolidCable
- Multi-tenant workspaces (Devise, Pundit, Pay)
- AI agent stack: chat, tools, agent tasks, effect tracking, scheduling
- RubyLLM with Anthropic, OpenAI, Google, Ollama support
- Inertia.js + React islands + Vite + TailwindCSS v4
- Vibes API sync surface (opt-in, fail-closed) for hosted-platform integration
