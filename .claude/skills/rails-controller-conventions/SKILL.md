---
name: rails-controller-conventions
description: Use when creating or modifying Rails controllers in app/controllers
---

# Rails Controller Conventions

Conventions for Rails controllers in this Ruby on Vibes app.

## Core Responsibilities

1. **Thin Controllers**: No business logic - delegate to models
2. **Request Handling**: Process parameters, handle formats, manage responses
3. **Authentication**: Already handled by ApplicationController (don't repeat)
4. **Routing**: Design clean, RESTful routes

## Critical: Authentication is Already Configured

```ruby
# ApplicationController already has:
class ApplicationController < ActionController::Base
  before_action :authenticate_user!  # ALL routes require auth by default
end
```

**NEVER add `before_action :authenticate_user!` in child controllers - it's inherited!**

For public routes, explicitly skip:
```ruby
class PublicController < ApplicationController
  skip_before_action :authenticate_user!, only: [:index, :show]
end
```

## Core Principles

1. **Message Passing OOP**: Ask objects, don't reach into their internals
2. **Turbo-first**: Use Turbo Streams, not JSON APIs (unless building v1 API)
3. **RESTful**: Stick to 7 standard actions, one controller per resource
4. **No Exception Control Flow**: Let exceptions propagate

## Message Passing (Critical)

**WRONG** - Reaching into associations:
```ruby
@bookmark = current_user.academy_bookmarks.find_by(academy: @academy)
```

**RIGHT** - Ask the object:
```ruby
@bookmark = current_user.bookmark_for(@academy)

# Model provides the answer
class User < ApplicationRecord
  def bookmark_for(academy)
    academy_bookmarks.find_by(academy: academy)
  end
end
```

## Stack-Specific Rules (Ruby on Vibes)

### Inertia Controllers
For SPA-like areas, use Inertia:
```ruby
class DashboardController < ApplicationController
  layout 'inertia'

  def show
    render inertia: 'Dashboard', props: {
      projects: current_user.projects.as_json
    }
  end
end
```

### API v1 Controllers
For JSON endpoints, use API namespace:
```ruby
# config/routes.rb
namespace :api do
  namespace :v1 do
    resources :projects
  end
end

# app/controllers/api/v1/projects_controller.rb
class Api::V1::ProjectsController < Api::V1::BaseController
  def index
    render json: @projects
  end
end
```

### Turbo Stream Responses (Default)
For ERB views with real-time updates:
```ruby
def create
  @project = current_user.projects.build(project_params)
  if @project.save
    respond_to do |format|
      format.turbo_stream
      format.html { redirect_to @project }
    end
  else
    render :new, status: :unprocessable_content
  end
end
```

### Prefix ID Lookups (Critical)
All models use `prefixed_ids` gem. The `prefix_id` is **not a database column** — it's computed from the record's numeric ID. The gem overrides `find` to accept both numeric IDs and prefix IDs seamlessly:

```ruby
# RIGHT
@project = Project.find(params[:id])  # works with "proj_abc123" or 42

# ALSO RIGHT (explicit)
@project = Project.find_by_prefix_id(params[:id])

# WRONG - prefix_id is NOT a column, this always returns nil
@project = Project.find_by(prefix_id: params[:id])
```

## Quick Reference

| Do | Don't |
|----|-------|
| `skip_before_action :authenticate_user!` for public | Add `before_action :authenticate_user!` |
| `user.bookmark_for(academy)` | `user.bookmarks.find_by(...)` |
| `layout 'inertia'` for SPA pages | Mix Inertia and ERB in same controller |
| Turbo Streams for ERB views | JSON responses (use API namespace instead) |
| 7 RESTful actions | Custom action proliferation |

## Common Mistakes

1. **Adding authenticate_user!** - It's already in ApplicationController
2. **Checking state in views** - Move to model method
3. **Business logic in controller** - Move to model
4. **Mixing Inertia and ERB layouts** - Pick one per controller
5. **Catching exceptions for control flow** - Let exceptions propagate
6. **`find_by(prefix_id: ...)`** - `prefix_id` is not a column. Use `find(params[:id])` which accepts prefix IDs automatically