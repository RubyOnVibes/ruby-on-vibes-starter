#!/usr/bin/env bash
# PostToolUse hook: Check Ruby syntax after file edits
#
# Runs `ruby -c` on any .rb file that was just written/edited.
# If syntax errors are found, injects the error into the model's context
# via additionalContext so the agent can fix it immediately.
#
# Performance: ruby -c takes ~50ms per file. Negligible overhead.

# Read JSON input from stdin (canonical SDK hook contract)
input=$(cat)

tool_name=$(echo "$input" | jq -r '.tool_name // empty')

# Collect file paths to check based on tool type
rb_files=""

case "$tool_name" in
  Edit|Write)
    fp=$(echo "$input" | jq -r '.tool_input.file_path // empty')
    if [[ "$fp" == *.rb && -f "$fp" ]]; then
      rb_files="$fp"
    fi
    ;;
  MultiEdit)
    # MultiEdit has an array of edits, each with a file_path
    # Use jq to filter to unique .rb paths directly
    rb_files=$(echo "$input" | jq -r '[.tool_input.edits[]?.file_path // empty] | unique[] | select(endswith(".rb"))' 2>/dev/null)
    ;;
  *)
    exit 0
    ;;
esac

# Nothing to check
[[ -z "$rb_files" ]] && exit 0

# Run syntax check on each .rb file
errors=""
while IFS= read -r fp; do
  [[ -z "$fp" ]] && continue
  [[ ! -f "$fp" ]] && continue
  result=$(ruby -c "$fp" 2>&1)
  if [[ $? -ne 0 ]]; then
    errors="${errors}${fp}:
${result}

"
  fi
done <<< "$rb_files"

# No errors — exit silently
[[ -z "$errors" ]] && exit 0

# Inject syntax errors into model context so the agent sees and fixes them
context="RUBY SYNTAX ERROR detected after your edit. Fix this before proceeding:

${errors}Read the file, find the syntax error, and correct it."

# Output JSON per SDK PostToolUse hook contract (stdout JSON with additionalContext)
jq -n \
  --arg ctx "$context" \
  '{
    "hookSpecificOutput": {
      "hookEventName": "PostToolUse",
      "additionalContext": $ctx
    }
  }'
