# ada.md - AI Coding Agent Context

Named after Ada Lovelace, the first programmer. This file provides essential context for AI coding agents (like Ada) working on this Rails app.

**For file-specific conventions**, the hooks system automatically loads skill files before editing:
- See `docs/SKILLS.md` for how the hooks/skills pattern works
- Skills are in `.claude/commands/*/SKILL.md`

---

## AI Systems Architecture

This app ships with AI-native infrastructure. These systems are dormant until used — no overhead if unused.

| System | What It Does | Key Files |
|--------|-------------|-----------|
| **Chat** | User ↔ AI conversations with streaming | `app/models/chat.rb`, `app/jobs/chat_stream_job.rb` |
| **Tools** | Inline actions during chat (fast, synchronous) | `app/tools/*.rb`, `app/services/toolset_service.rb` |
| **Agent Tasks** | Background work with progress tracking | `app/models/agent_task.rb`, `app/jobs/agent_task_job.rb` |
| **Persistent Agents** | Named autonomous workers with identity + memory | `app/models/agent.rb`, `config/agent_blueprints.yml` |
| **Webhooks** | External events trigger agent runs | `app/controllers/api/v1/webhooks_controller.rb` |

**When to use what:**
- **Tool** → completes in <10s, result needed in conversation (e.g., look up a record, fetch a URL)
- **Agent Task** → long-running background work with progress (e.g., process CSV, send batch emails)
- **Persistent Agent** → autonomous worker triggered by schedule or webhook (e.g., daily report, Stripe event handler)

**Deep docs:** `docs/building_with_agents.md` (tools + tasks), `docs/webhooks.md` (webhook integration)

---

## Stack Overview

- **Rails 8.1**, Ruby 3.4.x, Vite for JS, Propshaft for assets
- **Falcon** web server with **async-job-adapter** for LLM streaming
- **SolidQueue** for most background jobs, async adapter for IO-heavy LLM work
- **SQLite** (development) or **PostgreSQL** (production)

**Agent mindset**: Production Rails on constrained hardware. Prefer simple, robust changes over cleverness.

---

## Multi-Tenancy Structure

- `User` has many `workspaces` via `Member` join table
- Each user has a personal workspace; team workspaces enable collaboration
- Use `current_workspace` and `current_member` helpers (NOT `current_account`)

---

## Secrets and Environment Variables

**Always use ENV variables** for secrets - never Rails credentials:

```ruby
# Correct
api_key = ENV.fetch('OPENAI_API_KEY')

# Wrong - don't use credentials
api_key = Rails.application.credentials.dig(:openai, :api_key)
```

Instruct users to set secrets via the **Secrets menu** (lock icon in UI).

---

## Configuration (vibes.yml)

`config/vibes.yml` is the single source of truth for app identity:
- `application_name`, `business_name`, `support_email`, etc.
- Backend: `RubyOnVibes.application_name`
- Frontend: `window.App.data()?.name`

### Shared Layout Data (ERB + Inertia)

Both layouts set `data-app` on `<body>` via `app_data_attrs` helper. JavaScript reads it via `window.App.data()`.

**Pattern**: Config-driven UI that works in both layouts:
```ruby
# vibes_helper.rb - single source of truth
def app_data_attrs
  { name: ..., navItems: nav_menu_items }.to_json
end
```

```javascript
// Component reads from global state (works in ERB islands + Inertia)
const appData = window.App?.data()
```

### Shared Components (ERB + Inertia)

For UI used in both ERB and Inertia pages, use **shared components** with thin wrappers:

```
components/notifications/NotificationBellWithDropdown.jsx  ← shared logic
    ↑                                    ↑
islands/NotificationsIconIsland.jsx   Navbar.jsx (Inertia)
(ERB wrapper, reads props)            (uses directly)
```

**ERB pages**: Stable ERB layout with small React islands for interactive parts only. See `navbar-conventions` skill.

**Inertia pages**: Use shared components directly with Inertia props.

### Feature Flags

| Flag | When to Enable |
|------|----------------|
| `payment_processors: [stripe]` | SaaS, subscriptions, e-commerce |
| `teams: true` | Team collaboration, multi-tenant B2B |
| `referrals: true` | Viral growth, invite-based signups |

---

## LLM/AI Feature Configuration

This app uses **RubyLLM** for AI features (chatbots, assistants, content generation, etc.) via the platform's AI proxy. **LLM features are enabled by default.**

### The Toggle: `lib/ruby_on_vibes.rb`

LLM features are controlled by a single variable in `lib/ruby_on_vibes.rb`:

```ruby
def self.llm?
  proxy_enabled = true  # ← CHANGE THIS to false to disable LLM features
  return proxy_enabled && ENV["USE_MOUNTED_VIBES"] == "true" && ENV["VIBES_AI_PROXY_URL"].present?
  # ... fallback logic below
end
```

**To disable LLM features**: Change `proxy_enabled = true` to `proxy_enabled = false`

**To re-enable LLM features**: Change `proxy_enabled = false` to `proxy_enabled = true`

### What This Controls

| Method | What It Gates |
|--------|---------------|
| `RubyOnVibes.llm?` | All LLM/AI functionality (RubyLLM gem access) |
| `RubyOnVibes.chat?` | Chat UI visibility (defaults to same as `llm?`) |

**Note**: `chat?` calls `llm?` by default. If you need chat UI without full LLM access (or vice versa), you can customize the `chat?` method separately.

### When to Disable LLM Features

**KEEP ENABLED** (default, `proxy_enabled = true`) for most apps — anything that could benefit from AI:
- AI chatbots or assistants
- Content generation (text, summaries, translations)
- AI-powered search or recommendations
- Natural language interfaces
- Any feature using RubyLLM gem

**DISABLE** (`proxy_enabled = false`) only for apps with clearly no AI component:
- Pure static sites or brochure pages
- Simple CRUD apps with zero intelligence features
- Apps where users bring their own API keys (use direct `ANTHROPIC_API_KEY` instead)

When in doubt, leave it enabled — there's no cost until API calls are actually made.

### How the Proxy Works

When `proxy_enabled = true` and running on the platform:
1. `config/initializers/ruby_llm.rb` configures RubyLLM to use `VIBES_AI_PROXY_URL`
2. API calls route through platform proxy (uses `VIBES_API_TOKEN` for auth)
3. Usage is billed via platform credits
4. Model allowlist is enforced by proxy

Users can bypass the proxy by setting their own `ANTHROPIC_API_KEY` in Secrets.

### Example: User Asks to Enable/Disable AI

**User says**: "Disable AI features" or "Remove the chat"
→ Edit `lib/ruby_on_vibes.rb`, change `proxy_enabled = true` to `proxy_enabled = false`

**User says**: "Enable AI features" or "Add chatbot support"
→ Edit `lib/ruby_on_vibes.rb`, change `proxy_enabled = false` to `proxy_enabled = true`

### Persistent Agents Toggle

Separate from the LLM toggle, persistent agents (Manager, webhooks, scheduled runs) have their own code flag:

```ruby
def self.agents?
  return true if ENV['AGENTS_ENABLED'] == 'true' # dev override
  agents_enabled = true  # ← CHANGE THIS to false to disable persistent agents
  agents_enabled && agent_tasks?
end
```

**To disable persistent agents**: Change `agents_enabled = true` to `agents_enabled = false`

**To re-enable persistent agents**: Change `agents_enabled = false` to `agents_enabled = true`

**KEEP ENABLED** (default, `agents_enabled = true`) for apps that need:
- Webhook-triggered automation (GitHub, Stripe, etc.)
- Scheduled autonomous runs (daily reports, monitoring)
- A Manager agent for workspace coordination

**DISABLE** (`agents_enabled = false`) for apps that:
- Only need human↔AI chat (no autonomous agents)
- Have no webhook or scheduled automation needs
- Want a simpler sidebar without agents section

**User says**: "Remove the agents" or "I just need chat"
→ Edit `lib/ruby_on_vibes.rb`, change `agents_enabled = true` to `agents_enabled = false`

**User says**: "Add webhook automation" or "I need scheduled agents"
→ Edit `lib/ruby_on_vibes.rb`, change `agents_enabled = false` to `agents_enabled = true`

---

## Frontend Architecture

### Choosing the Right Approach

**Default: ERB + Alpine.js** unless you have a reason for Inertia.

| Scenario | Use |
|----------|-----|
| CRUD pages, forms, simple UI | ERB + Alpine.js |
| Complex widget in ERB page | IslandJS React component |
| Resource already uses Inertia | Inertia (stay consistent) |
| User explicitly requests React/SPA | Inertia |

**Rule**: Don't mix ERB and Inertia within the same resource.

### Alpine.js (Simple Interactivity)

Loaded via CDN with Turbo shim. Use `style="display: none;"` on initially hidden `x-show` elements.

---

## Theme and Styling

Tailwind v4 `@theme inline` registers semantic color names. Tailwind auto-generates all utilities (`bg-primary`, `text-foreground`, `border-border`, etc.) from these tokens.

**The default Tailwind palette is DISABLED** (`--color-*: initial`). Colors like `bg-gray-500`, `text-blue-600`, `border-red-300` will produce NO styling. ONLY use semantic color names.

```erb
<div class="bg-background text-foreground">
<div class="bg-primary text-primary-foreground">
<div class="bg-surface-1 hover:bg-surface-2">
<div class="bg-destructive/10 text-destructive">  <%# opacity via /N syntax %>
```

**Available semantic colors** (use with `bg-`, `text-`, `border-`, `ring-`, `from-`, `to-`, etc.):
- **Core**: `background`, `foreground`, `primary`, `primary-foreground`, `secondary`, `secondary-foreground`, `accent`, `accent-foreground`, `muted`, `muted-foreground`
- **UI**: `destructive`, `destructive-foreground`, `border`, `input`, `ring`, `card`, `card-foreground`, `popover`, `popover-foreground`
- **Surfaces**: `surface-0`, `surface-1`, `surface-2`, `surface-3`
- **Status**: `info`, `info-foreground`, `warning`, `warning-foreground`, `success`, `success-foreground`
- **Chart**: `chart-1`, `chart-2`, `chart-3`, `chart-4`, `chart-5` (data visualization)
- **Preserved**: `white`, `black`, `transparent`, `current`

**Component classes**: `btn btn-primary`, `btn btn-secondary`, `btn btn-destructive`, `btn btn-ghost`, `v-link`, `v-link-muted`

**Opacity**: Use `/N` suffix — `bg-primary/10`, `text-foreground/60`, `border-border/50`

**Gradients**: `from-primary to-accent`, `from-surface-0 to-surface-1`

**NEVER invent `v-*` prefixed classes** — they don't exist except the few above.
**NEVER use default Tailwind palette** — `gray-*`, `blue-*`, `red-*`, `slate-*`, `indigo-*`, etc. are all disabled.

### JSX Inline Styles

In React components, use `var(--color-*)` in `style` props — NOT hardcoded RGB:

```jsx
// RIGHT — auto-switches in dark mode
<div style={{ color: 'var(--color-foreground)', backgroundColor: 'var(--color-surface-1)' }}>
<button style={{ color: 'var(--color-destructive)' }}>Delete</button>

// WRONG — breaks theming and dark mode
<div style={{ color: 'rgb(17 24 39)' }}>

// Opacity in inline styles: use color-mix()
style={{ backgroundColor: 'color-mix(in srgb, var(--color-destructive) 10%, transparent)' }}

// WRONG — never use light/dark conditionals for colors
background: theme === 'dark' ? 'rgb(31 41 55)' : 'white'  // Use var(--color-surface-1) instead
```

### Changing vs. Extending Colors

**Changing brand colors** (e.g., blue → green): Edit `app/helpers/vibes_helper.rb` only (1 file). Change the RGB value for `brand:` in `vibes_tokens` and `vibes_tokens_dark`. CSS variables cascade automatically.

**Adding NEW semantic colors** (e.g., `highlight`): Requires editing 3 files. Load the `theme-conventions` skill for instructions.

### Dark Mode

Class-based (not media query). Toggle adds `.dark` to `<html>`. Semantic colors auto-switch — no `dark:` prefix needed for colors. Test with:
```javascript
document.documentElement.classList.add('dark');
```

---

## AI Response Formatting

- Always produce **valid Markdown** (blank line after headings)
- Keep responses **concise but complete**
- Include exact text when user requested specific content
- Use `<!-- VIBES_SUMMARY_START -->` delimiter for hybrid content

---

## Hooks & Skills System

This app uses Claude Code's hooks to enforce conventions before file edits.

### How It Works

1. **PreToolUse hook** fires before Edit/Write
2. Hook checks if file matches a pattern (e.g., `*/app/models/*.rb`)
3. If matched, blocks edit until relevant skill is loaded
4. Agent loads skill, reads conventions, retries
5. Edit proceeds

### Adding New Conventions

When establishing a new pattern that future agents should follow:

1. **Create skill file**: `.claude/commands/my-conventions/SKILL.md`
   ```markdown
   ---
   name: my-conventions
   description: Use when editing X files
   ---
   # My Conventions
   ...
   ```

2. **Add hook check** in `.claude/hooks/rails-conventions.sh`:
   ```bash
   if [[ "$file_path" == */path/pattern/*.rb ]]; then
     if skill_loaded "my-conventions"; then
       exit 0
     else
       deny_without_skill "my-conventions" "file type"
     fi
   fi
   ```

3. **Make hook executable**: `chmod +x .claude/hooks/*.sh`

### Current File → Skill Mappings

| Pattern | Skill |
|---------|-------|
| `*/_vibes_theme.html.erb`, `*/tailwind/vibes_theme.css` | theme-conventions |
| `*/app/models/*.rb` | rails-model-conventions |
| `*/app/controllers/*.rb` | rails-controller-conventions |
| `*/db/migrate/*.rb` | rails-migration-conventions |
| `*/app/jobs/*.rb` | rails-job-conventions |
| `*/spec/*.rb` | rails-testing-conventions |
| `*/app/javascript/pages/*.jsx` | inertia-page-conventions |
| `*/app/javascript/islands/*.jsx` | island-component-conventions |
| `*/app/javascript/components/*.jsx` | shared-component-conventions |
| `*/app/tools/*.rb` | ruby-llm-tools-conventions |
| `*/_navbar.html.erb`, `*/components/navbar/NavbarCore.jsx`, `*/islands/components/*IconIsland.jsx`, `*/islands/components/*DropdownIsland.jsx` | navbar-conventions |

**Note:** Regular views, helpers, and `vibes_helper.rb` no longer require the theme skill — color usage rules are in this file (ada.md). The theme skill is only needed when editing theme infrastructure files.
