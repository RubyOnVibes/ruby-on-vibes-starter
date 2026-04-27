# Workspaces & Members

This app includes a built-in **multitenancy system** using Workspaces and Members. This allows users to belong to multiple workspaces and collaborate with team members.

## What is Multitenancy?

**Multitenancy** means your app can support multiple separate workspaces (workspaces) where users can collaborate. Think of how Slack, GitHub, or Linear work - you can be part of multiple teams, each with its own data and members.

## Core Concepts

### Workspaces

An **Workspace** represents a workspace or team. Each workspace:
- Has an owner (the user who created it)
- Can have multiple members
- Has its own isolated data
- Can be either:
  - **Personal** - Automatically created for each user
  - **Team** - Created manually for collaboration (like "Acme Inc Team")

### Members

A **Member** represents a user's membership in a workspace. Each member has:
- A reference to the user
- A reference to the workspace
- **Roles** (stored as JSON):
  - `admin` - Can manage workspace settings and members
  - `member` - Basic access to workspace resources

## Key Files

- `app/models/workspace.rb` - Workspace model
- `app/models/member.rb` - Member model (join between User and Workspace)
- `app/controllers/workspaces_controller.rb` - Workspace CRUD
- `app/controllers/members_controller.rb` - Member management
- `app/controllers/invitations_controller.rb` - Invite users to workspaces
- `app/policies/` - Pundit policies for authorization

## Scoping Data to Workspaces

All workspace-scoped models should belong to a workspace:

```ruby
class Project < ApplicationRecord
  belongs_to :workspace
end
```

Controllers scope queries through the current workspace:

```ruby
def index
  @projects = current_workspace.projects
end
```

## Personal vs Team Workspaces

Every user gets a **personal workspace** automatically on sign-up. Personal workspaces have a single member (the owner).

**Team workspaces** are created manually and support multiple members with role-based access. Enable teams in `config/vibes.yml`:

```yaml
teams: true
```

## Invitations

Users are invited to workspaces via email. The invitation flow:
1. Admin sends invite from workspace settings
2. Invitee receives email with accept link
3. On accept, a Member record is created with the `member` role