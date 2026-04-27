# Claude Code Skills System

This app uses Claude Code's hooks and skills system to enforce coding conventions.

## How It Works

1. **PreToolUse hook** fires before any Edit/Write operation
2. Hook checks if the target file matches a pattern (e.g., `*/db/migrate/*.rb`)
3. If matched, hook blocks the edit until the relevant skill is loaded
4. Claude loads the skill, reads the conventions, then retries
5. Hook allows the edit (skill is now in transcript)

## File Structure

```
.claude/
├── settings.json              # Hook configuration
├── hooks/
│   └── rails-conventions.sh   # PreToolUse hook script
└── commands/
    ├── rails-model-conventions/SKILL.md
    ├── rails-controller-conventions/SKILL.md
    ├── rails-migration-conventions/SKILL.md
    ├── rails-job-conventions/SKILL.md
    ├── rails-testing-conventions/SKILL.md
    ├── inertia-page-conventions/SKILL.md
    └── island-component-conventions/SKILL.md
```

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

## Adding New Skills

1. Create `.claude/commands/my-skill/SKILL.md` with frontmatter:
   ```markdown
   ---
   name: my-skill
   description: When to use this skill
   ---
   # My Skill
   Conventions go here...
   ```

2. Add pattern check to `.claude/hooks/rails-conventions.sh`:
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

- Hook script must be executable: `chmod +x .claude/hooks/*.sh`
- Requires `jq` for JSON parsing
- SDK must use `settingSources: ['project']` to load hooks
