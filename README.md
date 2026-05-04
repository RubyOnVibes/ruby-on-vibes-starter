# Ruby on Vibes Starter

An opinionated, AI-enhanced Rails 8 template for building agentic web applications. Chat with an AI assistant that can look things up, run background tasks autonomously, track its work, and report back — all on production-ready infrastructure.

Built on Falcon (async fiber-based web server), SolidQueue (background jobs), RubyLLM (multi-provider AI), and Inertia.js (React islands + Turbo).

## Community

- **Website:** [rubyonvibes.com](https://rubyonvibes.com)
- **Discord:** [Join the community](https://discord.gg/DrfUKhtFmD)

## Quickstart

```bash
git clone <your-fork-url>
cd <your-app>
bin/setup        # bundle, db:prepare, JS deps
bin/dev          # Falcon + SolidQueue + Vite + Tailwind
```

Open http://localhost:3000.

Set at least one LLM provider key before chat will work:

```bash
cp .env.example .env
# then add ANTHROPIC_API_KEY=... or OPENAI_API_KEY=... or GEMINI_API_KEY=...
```

## Architecture

- **Fiber-based chat**: `ChatStreamJob` runs as an in-process fiber via `async-job`. LLM streaming, tool calls, and HTTP requests all yield during I/O — no thread starvation, no blocked workers.
- **Background agent tasks**: Long-running work runs in SolidQueue as a separate process. Progress tracking, retries, cancellation, and audit trails built in.
- **Multi-tenant**: Workspaces, members, roles, and permissions from day one.
- **Any LLM provider**: Anthropic, OpenAI, Google, local models via Ollama — set an env var and go.

## Documentation

All guides live in `docs/`. Start here:

### Building with Agents

How to add AI-powered capabilities using tools and agent tasks.

**Location:** `docs/building_with_agents.md`

**Covers:**
- Tools vs Agent Tasks — when to use each
- Creating inline tools (fast, run in the chat fiber)
- Creating agent tasks (background, long-running, with retries and progress)
- Effect tracking for audit trails
- Decision guide and file conventions

### Workspaces & Members

Guide to the built-in multitenancy system.

**Location:** `docs/workspaces.md`

**Covers:**
- Workspace and Member models
- Personal vs Team workspaces
- Roles, permissions, invitations
- Scoping data to workspaces
- Billing integration

### Additional Docs

- `docs/contexts.md` — Record context system for @mentions
- `docs/mentionable.md` — Mentionable module for chat references
- `docs/notifications.md` — Notification system
- `docs/queue.md` — SolidQueue configuration
- `docs/cache.md` — SolidCache configuration
- `docs/ssr.md` — Server-side rendering with Inertia
- `docs/javascript.md` — JavaScript/React architecture
- `docs/Tailwind.md` — TailwindCSS v4 setup
- `docs/pagination.md` — Pagy pagination
- `docs/prefixed_ids.md` — Prefix ID system
- `docs/email.md` — Email configuration
- `docs/deployment/` — SQLite and PostgreSQL deployment guides
- `docs/vibes-api.md` — Hosted-platform sync surface (off by default; see security note)

## Key Directories

```
app/tools/           — AI tool classes (RubyLLM::Tool subclasses)
app/jobs/            — Background jobs (AgentTaskJob subclasses for tasks)
app/models/          — Models including AgentTask, AgentTaskEffect
app/services/        — ToolsetService (tool registration), business logic
app/controllers/api/ — JSON API endpoints (task polling, chat)
app/javascript/      — React components (Inertia islands)
docs/                — All documentation
```

## Deployment

The template ships with multiple deploy paths so you can pick one:

- `Dockerfile` — production container, used by all platforms below.
- `fly.toml` — Fly.io. Set `app = "<your-app>"` and update `[build] image = "..."` to point at your own registry tag before `flyctl deploy`. (The hosted Ruby on Vibes platform auto-rewrites both fields during its image build pipeline; if you're forking the template to deploy yourself, you own them.)
- `render.sqlite.yaml` / `render.postgres.yaml` — Render Blueprint configs. Replace `REPLACE_ME` placeholders with your service name. See `docs/deployment/`.
- `.kamal/` — Kamal config (Docker-based VPS deploys).

## Optional Modules

Several gems and features are optional and can be removed or disabled:

- **Billing (Stripe + Pay + Receipts)** — disable in `config/vibes.yml` (`payment_processors: []`).
- **Admin panel (Madmin)** — remove the gem if you'll build your own admin UI.
- **Analytics (Blazer + Ahoy)** — remove if you don't need internal dashboards.
- **Mailbin** — auto-mounts at `/mailbin` in development; production opts in only when no real mailer is configured.
- **MCP introspection (Tidewave)** — only activates when `TIDEWAVE_ENABLED=true` and a shared secret is set.

## Security Note: Vibes API

`app/controllers/vibes/api/` exposes endpoints used by the hosted Ruby on Vibes platform to sync code into running app instances. **They are off by default.** They only mount when `VIBES_API_ENABLED=true`, and authentication fails closed if `VIBES_API_TOKEN` is unset. If you self-host, leave both unset unless you're sure you need them. See `docs/vibes-api.md`.

## License

MIT — see [LICENSE](LICENSE).

## Upgrades

For Rails upgrade guidance: https://github.com/ombulabs/claude-code_rails-upgrade-skill
