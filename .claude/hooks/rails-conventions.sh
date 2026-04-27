#!/bin/bash
# PreToolUse hook: Enforce Rails conventions skills before editing Rails files
# Adapted from obra/superpowers for Ruby on Vibes SDK context
#
# Uses deny-until-skill-loaded pattern - blocks edits until required skill is loaded
# Exit codes:
#   0 = allow the edit
#   2 = block the edit (skill not loaded)

# Read JSON input from stdin
input=$(cat)

tool_name=$(echo "$input" | jq -r '.tool_name // empty')
file_path=$(echo "$input" | jq -r '.tool_input.file_path // empty')
skill_name=$(echo "$input" | jq -r '.tool_input.skill // empty')
transcript_path=$(echo "$input" | jq -r '.transcript_path // empty')

# Always allow Skill tool (loading skills)
if [[ "$tool_name" == "Skill" && -n "$skill_name" ]]; then
  exit 0
fi

# Exit early if no file_path (not a file operation)
if [[ -z "$file_path" ]]; then
  exit 0
fi

# Function to check if skill was loaded in transcript
skill_loaded() {
  local skill="$1"
  if [[ -n "$transcript_path" && -f "$transcript_path" ]]; then
    if grep -q "\"skill\": \"$skill\"" "$transcript_path" 2>/dev/null || \
       grep -q "\"skill\":\"$skill\"" "$transcript_path" 2>/dev/null; then
      return 0
    fi
  fi
  return 1
}

# Function to deny with message - uses exit code 2 to block
deny_without_skill() {
  local skill="$1"
  local file_type="$2"

  cat >&2 << EOF
BLOCKED: You must load the $skill skill before editing $file_type files.

STOP. Do not immediately retry your edit.
1. Load the skill: Skill(skill: "$skill")
2. Read the conventions carefully
3. Reconsider whether your planned edit follows them
4. Adjust your approach if needed, then edit
EOF
  exit 2
}

# Theme infrastructure files — require theme-conventions skill
# These files use non-obvious formats (space-separated RGB triplets) and a
# strict 3-file workflow; editing them wrong breaks the whole app.
if [[ "$file_path" == */_vibes_theme.html.erb ]] ||
   [[ "$file_path" == */app/assets/tailwind/vibes_theme.css ]] ||
   [[ "$file_path" == */vibes_helper.rb ]]; then
  if skill_loaded "theme-conventions"; then
    exit 0
  else
    deny_without_skill "theme-conventions" "theme infrastructure"
  fi
fi

# Check if this is a Rails controller file
if [[ "$file_path" == */app/controllers/*.rb ]]; then
  if skill_loaded "rails-controller-conventions"; then
    exit 0
  else
    deny_without_skill "rails-controller-conventions" "controller"
  fi
fi

# Check if this is a Rails model file
if [[ "$file_path" == */app/models/*.rb ]]; then
  if skill_loaded "rails-model-conventions"; then
    exit 0
  else
    deny_without_skill "rails-model-conventions" "model"
  fi
fi

# Check if this is a Rails job file
if [[ "$file_path" == */app/jobs/*.rb ]]; then
  if skill_loaded "rails-job-conventions"; then
    exit 0
  else
    deny_without_skill "rails-job-conventions" "job"
  fi
fi

# Check if this is a database migration file
if [[ "$file_path" == */db/migrate/*.rb ]]; then
  if skill_loaded "rails-migration-conventions"; then
    exit 0
  else
    deny_without_skill "rails-migration-conventions" "migration"
  fi
fi

# Check if this is a spec file
if [[ "$file_path" == */spec/*.rb ]]; then
  if skill_loaded "rails-testing-conventions"; then
    exit 0
  else
    deny_without_skill "rails-testing-conventions" "spec"
  fi
fi

# Check if this is an Inertia/React page file
if [[ "$file_path" == */app/javascript/pages/*.tsx ]] || [[ "$file_path" == */app/javascript/pages/*.jsx ]]; then
  if skill_loaded "inertia-page-conventions"; then
    exit 0
  else
    deny_without_skill "inertia-page-conventions" "Inertia page"
  fi
fi

# Check if this is an IslandJS React component
if [[ "$file_path" == */app/javascript/islands/*.tsx ]] || [[ "$file_path" == */app/javascript/islands/*.jsx ]]; then
  if skill_loaded "island-component-conventions"; then
    exit 0
  else
    deny_without_skill "island-component-conventions" "island component"
  fi
fi

# Check if this is a RubyLLM tool file
if [[ "$file_path" == */app/tools/*.rb ]]; then
  if skill_loaded "ruby-llm-tools-conventions"; then
    exit 0
  else
    deny_without_skill "ruby-llm-tools-conventions" "RubyLLM tool"
  fi
fi

# Check if this is a navbar-related file (_navbar.html.erb or notification/user menu islands)
if [[ "$file_path" == */_navbar.html.erb ]] ||
   [[ "$file_path" == */components/navbar/NavbarCore.jsx ]] ||
   [[ "$file_path" == */islands/components/NotificationsIconIsland.jsx ]] ||
   [[ "$file_path" == */islands/components/UserMenuDropdownIsland.jsx ]]; then
  if skill_loaded "navbar-conventions"; then
    exit 0
  else
    deny_without_skill "navbar-conventions" "navbar"
  fi
fi

# Check if this is a settings sidebar file (ERB, island, core, wrapper, or layout)
if [[ "$file_path" == */_sidebar_nav.html.erb ]] ||
   [[ "$file_path" == */islands/components/SettingsSidebarIsland.jsx ]] ||
   [[ "$file_path" == */components/settings/SettingsSidebarCore.jsx ]] ||
   [[ "$file_path" == */components/settings/SettingsSidebar.jsx ]] ||
   [[ "$file_path" == */layouts/SettingsLayout.jsx ]]; then
  if skill_loaded "settings-sidebar-conventions"; then
    exit 0
  else
    deny_without_skill "settings-sidebar-conventions" "settings sidebar"
  fi
fi

# Check if this is a shared React component (used by both Inertia and islands)
# Excludes navbar and settings (have their own skills) and pages/islands (have their own skills)
if [[ "$file_path" == */app/javascript/components/*.tsx ]] ||
   [[ "$file_path" == */app/javascript/components/*.jsx ]]; then
  # Skip if already handled by navbar-conventions or settings-sidebar-conventions
  if [[ "$file_path" != */components/navbar/* ]] && [[ "$file_path" != */components/settings/* ]]; then
    if skill_loaded "shared-component-conventions"; then
      exit 0
    else
      deny_without_skill "shared-component-conventions" "shared component"
    fi
  fi
fi

# For other files, proceed normally
exit 0
