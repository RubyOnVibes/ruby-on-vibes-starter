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

Done. Users can now @mention projects in chat.

## How It Works

1. **User types @** -> autocomplete searches via MentionablesController
2. **User selects** -> mention stored with message
3. **LLM receives** -> structured context (via RecordContext if available)
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

## Structured LLM Context (Recommended)

Create a RecordContext for schema-driven serialization:

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

The Mentionables module auto-discovers `ProjectContext` for `Project` models.

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

See `app/controllers/api/v1/mentionables_controller.rb` for examples.
