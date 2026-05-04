---
name: rails-model-conventions
description: Use when creating or modifying Rails models in app/models
---

# Rails Model Conventions

Conventions for Rails models in this Ruby on Vibes app.

## Core Principles

1. **Business logic lives here** - Models own ALL domain logic, not controllers
2. **Clean interfaces** - Don't leak implementation details
3. **Message passing** - Ask objects, don't reach into their associations
4. **Pass objects, not IDs** - Method signatures should accept domain objects
5. **Compose with concerns** - Use namespaced concerns (`Card::Closeable` in `card/closeable.rb`)

## Reciprocal Associations (Critical)

**When you add or update an association to ANY model, you MUST update BOTH sides.**

ActiveRecord associations are bidirectional. If you add `belongs_to` on one model, you MUST add the corresponding `has_many`/`has_one` on the other model. Failure to do this breaks views that traverse the relationship.

```ruby
# WRONG - only one side declared
# app/models/task.rb
class Task < ApplicationRecord
  belongs_to :project  # Added this...
end
# app/models/project.rb
class Project < ApplicationRecord
  # ...but forgot has_many :tasks here!
end
# Views break: project.tasks => NoMethodError

# RIGHT - BOTH sides declared
# app/models/task.rb
class Task < ApplicationRecord
  belongs_to :project
end
# app/models/project.rb
class Project < ApplicationRecord
  has_many :tasks, dependent: :destroy  # ALWAYS add the inverse
end
```

**Checklist when adding associations:**
1. Add `belongs_to :parent` on the child model
2. Add `has_many :children` (or `has_one`) on the parent model
3. Add `:dependent` option (`:destroy`, `:nullify`, etc.)
4. Add `:inverse_of` if Rails can't infer it (polymorphic, custom names)
5. Add foreign key index in migration

**Common patterns requiring BOTH sides:**
- `Task belongs_to :project` → `Project has_many :tasks`
- `Comment belongs_to :member` → `Member has_many :comments`
- `Attachment belongs_to :attachable (polymorphic)` → `Post has_many :attachments, as: :attachable`

### Counter Caches
If you use `counter_cache: true`, you **must** also add the count column on the parent table. Without it, Rails silently does nothing.

```ruby
# WRONG - counter_cache with no column (silently broken)
class Task < ApplicationRecord
  belongs_to :project, counter_cache: true  # expects projects.tasks_count column
end
# But projects table has no tasks_count column!

# RIGHT - counter_cache WITH migration
class Task < ApplicationRecord
  belongs_to :project, counter_cache: true
end

# Migration:
add_column :projects, :tasks_count, :integer, default: 0, null: false
```

Column naming: `#{association_name}_count` on the **parent** table (e.g., `tasks_count` on `projects`).

**STOP and check:** Before finishing any model work, verify you updated ALL related models with their reciprocal associations.

## Clean Interfaces (Critical)

```ruby
# WRONG - leaking implementation
user.bookmarks.where(academy: academy).exists?
user.bookmarks.create!(academy: academy)

# RIGHT - clean interface
user.bookmarked?(academy)
user.bookmark(academy)

# Model exposes intent-based methods
class User < ApplicationRecord
  def bookmarked?(academy)
    academy_bookmarks.exists?(academy: academy)
  end

  def bookmark(academy)
    academy_bookmarks.find_or_create_by(academy: academy)
  end
end
```

## Organization

Order: constants -> associations -> validations -> scopes -> callbacks -> public methods -> private methods

## Stack-Specific Rules (Ruby on Vibes)

### Enums
Use the new symbol syntax:
```ruby
# RIGHT
enum :status, { draft: 0, published: 1 }

# WRONG (old syntax)
enum status: { draft: 0, inactive: 1 }
```

### Prefix IDs
Models use `prefixed_ids` gem - the `prefix_id` is a virtual attribute (NOT a column):
```ruby
# Declaration
class Project < ApplicationRecord
  has_prefix_id :proj
end

# WRONG - prefix_id is NOT a database column
Project.find_by(prefix_id: "proj_abc123")  # NO! Returns nil always

# RIGHT - the gem overrides `find` to accept prefix IDs
Project.find("proj_abc123")               # works (also accepts numeric IDs)
Project.find_by_prefix_id("proj_abc123")  # works (prefix ID only)

# WRONG - never add a prefix_id column in migrations
add_column :projects, :prefix_id, :string  # NO!
```

### Mentionable Pattern
For models that can be @mentioned in chat:
```ruby
class Project < ApplicationRecord
  include Mentionable

  def mentionable_summary
    "#{tasks.count} tasks, updated #{updated_at.to_formatted_s(:short)}"
  end
end
```

## Guidelines

- **Validations** - Use built-in validators, validate at model level
- **Associations** - Use `:dependent`, `:inverse_of`, counter caches
- **Scopes** - Named scopes for reusable queries
- **Callbacks** - Use sparingly, never for external side effects (emails, APIs)
- **Queries** - Never raw SQL, use ActiveRecord/Arel. Avoid N+1 with `includes`

## Quick Reference

| Do | Don't |
|----|-------|
| Update BOTH models when adding associations | Only add `belongs_to` without `has_many` |
| `Card::Closeable` in `card/closeable.rb` | All logic in `card.rb` |
| `user.bookmark(academy)` | `user.bookmarks.create(...)` |
| `enum :status, { ... }` | `enum status: { ... }` |
| `find(prefix_id)` or `find_by_prefix_id` | `find_by(prefix_id: ...)` (not a column!) |
| Intent-based method names | Exposing associations directly |

## Mentionable Interface

Models that can be @mentioned in chat include `Mentionable`. Read `app/models/concerns/mentionable.rb` for the interface.

```ruby
class Project < ApplicationRecord
  include Mentionable

  # Override for custom display (all optional)
  def mentionable_label
    name
  end

  def mentionable_summary
    "#{tasks.count} tasks, #{status}"
  end
end
```

**Overridable instance methods:**
- `mentionable_label` - Display name (defaults to name/title/email)
- `mentionable_path` - URL path for linking
- `mentionable_kind` - Type identifier for UI
- `mentionable_summary` - Brief summary for LLM context

**CRITICAL: Update the controller when adding mentionables.** Search logic lives in `app/controllers/api/v1/mentionables_controller.rb`. When you make a model mentionable, you MUST also add a searcher method to the controller and register it in the `SEARCHERS` constant. Read that file for the pattern.

**Do NOT hallucinate methods** - The concern has NO class methods. Read the file if unsure.

## RecordContext (LLM Context Serialization)

For structured LLM context, create a context class in `app/models/contexts/`.

- Base class: `app/models/contexts/record_context.rb`
- Example: `app/models/contexts/member_context.rb` (read this for the pattern)

**Critical: RubyLLM Schema uses `string` not `text`** - Even for text/longtext columns, use `string` in the schema DSL.

## Common Mistakes

1. **One-sided associations** - When adding `belongs_to`, ALWAYS add `has_many`/`has_one` on the other model. Views will break with NoMethodError if you forget the reciprocal side.
2. **Anemic models** - Business logic belongs in models, not controllers
3. **Leaking implementation** - Provide clean interface methods
4. **Old enum syntax** - Use new symbol-based syntax
5. **Prefix ID misuse** - `prefix_id` is NOT a column. Never use `find_by(prefix_id: ...)`. Use `find(id_or_prefix)` or `find_by_prefix_id(prefix)`
6. **N+1 queries** - Use counter_cache, includes, eager loading
7. **Hallucinating Mentionable methods** - Read the concern file; it has NO class methods
8. **Using `text` in RubyLLM schema** - Use `string` for all text types
9. **Forgetting MentionablesController** - When adding `include Mentionable`, also update the controller