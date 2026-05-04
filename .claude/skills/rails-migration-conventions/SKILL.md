---
name: rails-migration-conventions
description: Use when creating or modifying database migrations in db/migrate
---

# Rails Migration Conventions

Conventions for database migrations in this Ruby on Vibes app.

## Core Principles

1. **Always reversible** - Every migration must roll back cleanly
2. **Never delete migrations** - Use forward-only strategy
3. **Consider existing data** - Migrations run against production with real rows
4. **Index foreign keys** - Every `_id` column gets an index
5. **Check database type** - SQLite uses `json`, PostgreSQL uses `jsonb`

## Critical: Forward-Only Strategy

**NEVER delete migration files that have been committed or deployed.**

When you need to fix or undo a migration:
- **Broken migrations that raised an error while running or haven't run**: Fix the broken migration file directly
- **Migrations that already ran**: Add a NEW migration to reverse changes

```ruby
# To undo a column addition, create a NEW migration:
class RemoveFooFromUsers < ActiveRecord::Migration[8.0]
  def change
    remove_column :users, :foo, :string
  end
end
```

## Critical: Index Safety

Rails' `add_reference` and `t.references` **already add an index by default**.

```ruby
# WRONG - double index
add_reference :comments, :user, foreign_key: true
add_index :comments, :user_id  # Already added by add_reference!

# RIGHT - check first
add_index :comments, :user_id unless index_exists?(:comments, :user_id)

# Or just let add_reference handle it
add_reference :comments, :user, foreign_key: true  # Index included
```

## Critical: Never Add prefix_id Columns

The `prefixed_ids` gem provides `prefix_id` as a virtual attribute.

```ruby
# WRONG - the gem handles this
add_column :projects, :prefix_id, :string

# RIGHT - just use has_prefix_id in the model
class Project < ApplicationRecord
  has_prefix_id :proj
end
```

## Data Safety

```ruby
# WRONG - fails if table has rows
add_column :users, :role, :string, null: false

# RIGHT - handle existing data
add_column :users, :role, :string, default: 'member'
change_column_null :users, :role, false
```

## JSON Columns

Check `config/database.yml` before adding JSON columns:

```ruby
# For SQLite
add_column :settings, :preferences, :json

# For PostgreSQL
add_column :settings, :preferences, :jsonb
```

## Quick Reference

| Do | Don't |
|----|-------|
| Forward-only (new migrations to undo) | Delete migration files |
| `unless index_exists?` guard | Duplicate indexes |
| Check database type for json/jsonb | Assume PostgreSQL |
| Handle existing data | Assume empty tables |
| Test rollback | Skip rollback testing |

## Common Mistakes

1. **Adding prefix_id column** - The gem handles this, no column needed
2. **Double indexes** - `add_reference` already adds an index
3. **Not null without default** - Fails on existing rows
4. **Deleting migrations** - Breaks git history and fresh db:migrate
5. **Wrong JSON type** - SQLite uses `json`, PostgreSQL uses `jsonb`

## Template

```ruby
class AddFooToBar < ActiveRecord::Migration[8.0]
  def change
    add_column :bars, :foo, :string, default: '', null: false
    add_index :bars, :foo unless index_exists?(:bars, :foo)
  end
end
```

**Remember:** Migrations run against production. Safe, reversible, data-aware, and forward-only.