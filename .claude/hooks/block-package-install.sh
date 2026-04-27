#!/bin/bash
# PreToolUse hook: Block package management commands in Bash
# Package installs happen automatically on the remote deploy server
# (HotBundleJob / HotYarnJob). The agent should edit Gemfile or
# package.json directly instead.
#
# Exit codes:
#   0 = allow the command
#   2 = block the command (stderr message shown to Claude as reason)

input=$(cat)

tool_name=$(echo "$input" | jq -r '.tool_name // empty')

# Only inspect Bash commands
if [[ "$tool_name" != "Bash" ]]; then
  exit 0
fi

command=$(echo "$input" | jq -r '.tool_input.command // empty')

if [[ -z "$command" ]]; then
  exit 0
fi

# Check for package management commands
# Match: yarn add/install/remove/upgrade, npm install/ci/uninstall/update,
#        bundle add/install/update/remove, gem install,
#        pnpm add/install/remove/update, pip install
if echo "$command" | grep -qE '(^|\s|&&|\|\||;)(yarn\s+(add|install|remove|upgrade)|npm\s+(install|ci|uninstall|update)|bundle\s+(add|install|update|remove)|gem\s+install|pnpm\s+(add|install|remove|update)|pip\s+install)(\s|$|;|&&|\|\|)'; then
  cat >&2 << 'EOF'
BLOCKED: Package management commands are not allowed.

Package installation runs automatically on the remote deployment server
(HotBundleJob / HotYarnJob). Running install commands locally pollutes
the git diff, wastes time, or hangs.

Instead:
- Edit `Gemfile` directly to add/remove Ruby gems
- Edit `package.json` directly to add/remove JS packages
- Never edit lock files (`yarn.lock`, `Gemfile.lock`, `package-lock.json`) — they are generated automatically
EOF
  exit 2
fi

exit 0
