# Changelog

## 2026-11-25 — Durable agent foundations

- Upgrade to Ruby 4.0.10, Rails 8.1.4.1, and RubyLLM 2.2.3, with current security tooling and patched frontend dependencies.
- Run chats durably through Solid Queue, with persisted inputs, native RubyLLM claims and tasks, recovery after worker interruption, and permission-aware approval/question resumes.
- Add named chat purposes built on RubyLLM's Agent DSL and authenticated file/artifact access using its FileStore and Active Storage.
- Share worker broadcasts through Solid Cable and preserve the common chat renderer for immutable RubyLLM messages.
- Keep the document intake demonstration on its own branch; the starter contains the reusable primitives.
- Establish standalone `main` as the canonical starter and document guarded synchronization into the platform's embedded template.

Validation includes 545 passing starter specs, the matching embedded-template suite, process-level recovery checks, and a separate 560-spec document intake demo with a local browser/worker-restart exercise. Live provider behavior and platform deployment compatibility remain separate validation steps. The repository's existing style-lint backlog remains open.

For existing databases, review [upgrade and migration notes](docs/maintenance-2026-11.md) and back up before migrating. See [agent foundations](docs/agent-foundations.md) for the design and its limits.

## v0.1.0 — Initial public release

First public release of the Ruby on Vibes Starter template.

- Rails 8 + Falcon + SolidQueue + SolidCache + SolidCable
- Multi-tenant workspaces (Devise, Pundit, Pay)
- AI agent stack: chat, tools, agent tasks, effect tracking, scheduling
- RubyLLM with Anthropic, OpenAI, Google, Ollama support
- Inertia.js + React islands + Vite + TailwindCSS v4
- Vibes API sync surface (opt-in, fail-closed) for hosted-platform integration
