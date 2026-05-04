---
name: ruby-llm-tools-conventions
description: Use when creating or modifying RubyLLM tools in app/tools
---

# RubyLLM Tools Conventions

Conventions for AI agent tools in this Ruby on Vibes app.

## Stack Context

- **RubyLLM** provides the tool interface for AI chat capabilities
- Tools live in `app/tools/` with `*_tool.rb` naming
- Tools are registered via `ToolsetService` (`app/services/toolset_service.rb`)
- Tools receive chat context (chat, sender_user, sender_member, sender_workspace)

## Core Principles

1. **Tools extend RubyLLM::Tool** - Follow the RubyLLM tool interface
2. **Context-aware** - Tools receive sender and workspace context for scoping
3. **Must be registered** - New tools must be added to `ToolsetService.tool_classes`
4. **Clear descriptions** - LLM uses the description to decide when to call the tool

## Tool Structure

```ruby
# app/tools/search_projects_tool.rb
class SearchProjectsTool < RubyLLM::Tool
  description <<~DESC
    Search for projects by name or status.

    WHEN TO USE THIS:
    - When the user asks to find or search for projects
    - When looking up project information by name
  DESC

  params do
    string :query, description: "Search term for project name", required: true
    string :status, description: "Filter by status (active, archived, all)", required: false
  end

  attr_reader :chat, :sender_user, :sender_member, :sender_workspace

  def initialize(chat:, sender_user: nil, sender_member: nil, sender_workspace: nil)
    @chat = chat
    @chat_workspace = chat.workspace
    @sender_user = sender_user
    @sender_member = sender_member
    @sender_workspace = sender_workspace

    # Chat members may be from a different workspace than the chat was created in.
    @same_workspace = sender_workspace.present? && sender_workspace == @chat_workspace
  end

  def execute(query:, status: nil)
    # Scope to sender's workspace for multi-tenant safety
    projects = @sender_workspace.projects.where("name ILIKE ?", "%#{query}%")
    projects = projects.where(status: status) if status.present? && status != "all"

    {
      results: projects.limit(10).map { |p| { id: p.to_param, name: p.name, status: p.status } },
      total_count: projects.count
    }
  rescue ActiveRecord::StatementInvalid => e
    { error: "Query failed: #{e.message}" }
  rescue => e
    { error: e.message }
  end
end
```

## Record Lookups in Tools

All models use `prefixed_ids` gem — `prefix_id` is **not a column**. Use `find` or `find_by_prefix_id`:

```ruby
# RIGHT
project = @sender_workspace.projects.find(project_id)
project = @sender_workspace.projects.find_by_prefix_id(project_id)

# WRONG - prefix_id is not a column
project = @sender_workspace.projects.find_by(prefix_id: project_id)
```

## Registering Tools (CRITICAL)

**After creating a tool, you MUST register it in `ToolsetService`:**

```ruby
# app/services/toolset_service.rb
def tool_classes
  [
    CurrentDateTimeTool,  # Returns current date/time in user's timezone
    WebFetchTool,         # Fetches and extracts text content from web pages
    SearchProjectsTool,   # <-- Add your new tool here
  ]
end
```

Without registration, the tool will NOT be available to the LLM.

## Context Architecture

Tools receive context about the message sender:

```ruby
def initialize(chat:, sender_user: nil, sender_member: nil, sender_workspace: nil)
  @chat = chat                          # The chat instance
  @chat_workspace = chat.workspace      # Workspace that owns the chat
  @sender_user = sender_user            # User who sent the message
  @sender_member = sender_member        # Member record (user in workspace)
  @sender_workspace = sender_workspace  # Sender's workspace (may differ from chat_workspace!)

  # Cross-workspace check — a member from workspace B can participate in workspace A's chat
  @same_workspace = sender_workspace.present? && sender_workspace == @chat_workspace
end
```

**Multi-tenant safety:** Always scope queries to `@sender_workspace` to prevent cross-workspace data leaks. Use `@chat_workspace` only when you need chat-level data (e.g., chat settings). Never assume `@chat_workspace == @sender_workspace`.

## Parameter DSL (`params do`)

The `params do` block defines what the LLM can pass to `execute`. Available types:

```ruby
params do
  string  :name, description: "...", required: true     # text
  integer :count, description: "...", required: false    # whole number
  number  :score, description: "...", required: false    # float
  boolean :active, description: "...", required: false   # true/false
  array   :tags, description: "..." do                   # list
    string  # item type
  end
  object  :filters, description: "..." do               # nested object
    string :status, description: "..."
  end
  any_of  :value, description: "..." do                  # union type
    string
    integer
  end
end
```

Use `with_params` for provider-specific metadata (e.g., `with_params(strict: true)`).

## Return Values

Three return types from `execute`:

| Return | Effect |
|--------|--------|
| **Hash or String** | Normal — result sent to LLM, conversation continues |
| **`halt "message"`** | Message returned directly, skips LLM continuation (saves tokens for simple confirmations) |
| **`RubyLLM::Content.new(text, attachments)`** | Rich content with file attachments |

## Error Handling

**Recoverable errors** — return `{ error: message }` so the LLM can inform the user:

```ruby
def execute(query:)
  results = @sender_workspace.projects.search(query)
  { results: results }
rescue SpecificError => e          # catch known errors first
  { error: "Search failed: #{e.message}" }
rescue => e                        # catch-all last
  { error: e.message }
end
```

**Unrecoverable errors** — raise (e.g., SSRF protection in `WebFetchTool`). The framework handles it.

## Writing Good Descriptions

The description tells the LLM when to use the tool:

```ruby
# ✅ Good - clear "when to use" guidance
description <<~DESC
  Search for projects by name or status.

  WHEN TO USE THIS:
  - When the user asks to find or search for projects
  - When looking up project information by name
DESC

# ❌ Bad - vague, LLM won't know when to use it
description "Does project stuff"
```

## Quick Reference

| Do | Don't |
|----|-------|
| Extend `RubyLLM::Tool` | Create custom base classes |
| Register in `ToolsetService.tool_classes` | Forget to register (tool won't work) |
| Use `params do` block with typed DSL | Use old `param` method |
| Set `@chat_workspace = chat.workspace` in init | Assume `@chat_workspace == @sender_workspace` |
| Scope queries to `@sender_workspace` | Query unscoped (security risk) |
| Include "WHEN TO USE THIS" in description | Vague descriptions |
| Return `{ error: message }` for recoverable errors | Raise exceptions for user-facing errors |
| Use `halt "msg"` for simple confirmations | Waste tokens on LLM round-trip for acks |

## Common Mistakes

1. **Forgetting to register** - Tool won't be available to LLM
2. **Not scoping to workspace** - Cross-tenant data leaks
3. **Assuming chat.workspace == sender_workspace** - Members can be from different workspaces
4. **Poor descriptions** - LLM won't know when to use the tool
5. **Raising exceptions** - Return `{ error: message }` instead for recoverable errors
6. **Missing context params** - Always accept the full context signature
7. **`find_by(prefix_id: ...)`** - Not a column. Use `find(id)` or `find_by_prefix_id(id)`

## Testing Tools

```ruby
# spec/tools/search_projects_tool_spec.rb
RSpec.describe SearchProjectsTool do
  let(:workspace) { create(:workspace) }
  let(:user) { workspace.owner }
  let(:member) { workspace.members.first }
  let(:chat) { create(:chat, member: member) }

  subject do
    described_class.new(
      chat: chat,
      sender_user: user,
      sender_member: member,
      sender_workspace: workspace
    )
  end

  describe "#execute" do
    it "returns matching projects" do
      create(:project, workspace: workspace, name: "Alpha Project")
      result = subject.execute(query: "Alpha")
      expect(result[:results].first[:name]).to eq("Alpha Project")
    end
  end
end
```