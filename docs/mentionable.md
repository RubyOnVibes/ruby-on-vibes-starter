# Mentionable Pattern

Enable @mentions for any model in chat with built-in LLM context.

## Quick Start

**1. Include concern** (app/models/project.rb):
```ruby
class Project < ApplicationRecord
  include Mentionable
end
```

**2. Add searcher** (app/controllers/api/v1/mentionables_controller.rb):
```ruby
SEARCHERS = {
  # ... existing searchers
  'Project' => :search_projects
}.freeze

private

def search_projects(query)
  scope = current_workspace.projects

  scope
    .where("LOWER(name) LIKE ?", "%#{query.downcase}%")
    .order(:name)
    .limit(@limit)
    .map(&:to_mention)
end
```

**3. Add an explicit admission/replay policy.** Extend the type allowlist in
`MessagesController::MENTIONABLE_TYPES` and the case in
`Chat#mentionable_scope`. For example, `when "Project" then member.workspace.projects`
keeps projects in the initiating member's workspace. Preserve the method's
current-chat membership guard, and apply any additional project visibility rules.

Autocomplete, message admission and replay must agree about which records can
be shared with the conversation. Add a revoked-access regression when extending
this policy.

## How It Works

1. **User types @** -> autocomplete searches via MentionablesController
2. **User selects** -> mention stored with message
3. **LLM receives** -> a bounded inline summary in user-role content after current actor access is checked
4. **User clicks** -> navigates to record

## Customization

Override methods in your model for custom behavior:

```ruby
class Project < ApplicationRecord
  include Mentionable

  # Display label for @mention chips
  def mentionable_label
    "#{code} - #{name}"
  end

  # Brief summary for LLM context (keep concise for token efficiency)
  def mentionable_summary
    "Project #{name}: #{tasks.count} tasks, status: #{status}"
  end

  # Custom routing (defaults to polymorphic_path)
  def mentionable_path
    admin_project_path(self)
  end
end
```

## Optional structured record data

Create a RecordContext when a feature needs an explicit structured serializer.
The default inline mention path uses `mentionable_summary`; it does not
automatically attach every RecordContext field:

```ruby
# app/models/contexts/project_context.rb
class ProjectContext < RecordContext
  schema do
    string :id
    string :name
    string :path
    integer :tasks_count
  end

  def self.from_record(project)
    new(
      id: project.to_param,
      name: project.name,
      path: project.mentionable_path,
      tasks_count: project.tasks.count
    )
  end
end
```

The Mentionables module discovers `ProjectContext` when feature code explicitly
calls `project.to_llm_context`. Authorize the record before serialization and
return its data in tool or user-role content, not application instructions.
Search scoping alone does not authorize later access or a business effect.

## Why Search Lives in the Controller

Search logic is explicitly defined per model in `MentionablesController`:

**Benefits:**
- No magic DSL to learn
- Security scoping is visible and explicit
- Easy to customize per model
- Standard Rails patterns (just ActiveRecord queries)

**Adding a new mentionable:**
1. `include Mentionable` in the model
2. Add searcher method to controller
3. Register in `SEARCHERS` constant
4. Extend `MessagesController::MENTIONABLE_TYPES` and `Chat#mentionable_scope`

See `app/controllers/api/v1/mentionables_controller.rb` for examples.

## Replay authorization

`Chat#mentionable_scope` is the shared admission and replay policy. It permits
current chat members and their workspaces, including cross-workspace group
participants; another chat must belong to the initiating member's accessible
chats. When adding a model, extend this explicit policy as well as autocomplete.

`ChatPurpose` sets the original run actor before native history loads. Each
replay resolves mention IDs through the current scope. Missing actors, unknown
types and revoked access leave opaque placeholders without loading record
labels or summaries. Previously saved conversation text remains history; this
check cannot retract facts already written into a message or summary.
