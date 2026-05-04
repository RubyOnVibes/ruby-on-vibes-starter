# Hooks & Skills System

This app uses a hooks-and-skills pattern to enforce coding conventions. A PreToolUse hook intercepts Edit/Write operations on convention-governed files and blocks the edit until the relevant skill has been loaded into the conversation.

## How It Works

1. **PreToolUse hook** fires before any Edit/Write operation
2. Hook checks if the target file matches a pattern (e.g., `*/db/migrate/*.rb`)
3. If matched, hook blocks the edit until the relevant skill is loaded
4. The agent loads the skill (Claude Code via the `Skill` tool, other agents via a `Read` of `.claude/skills/<name>/SKILL.md`)
5. Hook allows the edit (skill is now in transcript)

## File Structure

```
.claude/
├── settings.json                          # Wires hooks → .claude/hooks/*.sh
├── hooks/
│   ├── rails-conventions.sh               # PreToolUse hook
│   ├── block-package-install.sh
│   └── ruby-syntax-check.sh
└── skills/
    ├── rails-model-conventions/SKILL.md   # Skill content + YAML frontmatter
    ├── rails-controller-conventions/SKILL.md
    ├── ...
    └── theme-conventions/SKILL.md
```

Each `SKILL.md` starts with YAML frontmatter (`name`, `description`) and is loaded by Claude Agent SDK as a model-invocable skill via the `Skill` tool. Non-Claude agents (Codex, Cursor, etc.) should `Read` the matching `SKILL.md` directly when editing files of that type — the conventions inside apply to any agent.

## File Pattern → Skill Mapping

| File Pattern | Required Skill |
|--------------|----------------|
| `*/app/models/*.rb` | rails-model-conventions |
| `*/app/controllers/*.rb` | rails-controller-conventions |
| `*/db/migrate/*.rb` | rails-migration-conventions |
| `*/app/jobs/*.rb` | rails-job-conventions |
| `*/spec/*.rb` | rails-testing-conventions |
| `*/app/javascript/pages/*.jsx` | inertia-page-conventions |
| `*/app/javascript/islands/*.jsx` | island-component-conventions |
| `*/app/tools/*.rb` | ruby-llm-tools-conventions |
| `*/_vibes_theme.html.erb`, `*/vibes_theme.css`, `*/vibes_helper.rb` | theme-conventions |
| `*/app/javascript/components/*.jsx` (excl. navbar/, settings/) | shared-component-conventions |
| `*/_navbar.html.erb`, `*/components/navbar/*`, navbar islands | navbar-conventions |
| `*/_sidebar_nav.html.erb`, `*/components/settings/*`, sidebar islands | settings-sidebar-conventions |

## Adding a New Skill

1. Write the skill at `.claude/skills/my-skill/SKILL.md`:
   ```markdown
   ---
   name: my-skill
   description: When to use this skill
   ---

   # My Skill

   ...conventions go here...
   ```

2. Add a pattern check to `.claude/hooks/rails-conventions.sh`:
   ```bash
   if [[ "$file_path" == */path/pattern/*.rb ]]; then
     if skill_loaded "my-skill"; then
       exit 0
     else
       deny_without_skill "my-skill" "file type"
     fi
   fi
   ```

## Requirements

- Hook scripts must be executable: `chmod +x .claude/hooks/*.sh`
- Requires `jq` for JSON parsing
- Claude Agent SDK must use `settingSources: ['project']` so `.claude/settings.json` (and the wired hooks) loads
