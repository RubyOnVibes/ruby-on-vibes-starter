---
name: inertia-page-conventions
description: Use when creating or modifying Inertia React pages in app/javascript/pages
---

# Inertia Page Conventions

Conventions for Inertia.js React pages in this Ruby on Vibes app.

## Stack Context

- **Inertia.js** connects Rails controllers to React pages
- Pages live in `app/javascript/pages/`
- Props come from Rails controllers, not client fetches
- Layout is `inertia.html.erb` (separate from `application.html.erb`)

## Core Principles

1. **Props are the data source** - Controllers send props, pages receive them
2. **No unnecessary fetches** - Data you need should come via props
3. **Shared components carefully** - Must work without ERB-only globals

## Page Structure

```jsx
// app/javascript/pages/Dashboard.jsx
import { Head } from '@inertiajs/react'

export default function Dashboard({ projects, currentUser }) {
  return (
    <>
      <Head title="Dashboard" />
      <div className="container mx-auto px-4">
        <h1>Welcome, {currentUser.firstName}</h1>
        <ProjectList projects={projects} />
      </div>
    </>
  )
}
```

## Controller Pattern

```ruby
# app/controllers/dashboard_controller.rb
class DashboardController < ApplicationController
  layout 'inertia'

  def show
    render inertia: 'Dashboard', props: {
      projects: current_user.projects.map { |p|
        { id: p.id, name: p.name, status: p.status }
      },
      currentUser: {
        email: current_user.email,
        firstName: current_user.first_name
      }
    }
  end
end
```

## Using Inertia Links

```jsx
import { Link } from '@inertiajs/react'

function Navigation() {
  return (
    <nav>
      <Link href="/dashboard">Dashboard</Link>
      <Link href="/projects" method="get">Projects</Link>
      <Link href="/logout" method="post" as="button">Logout</Link>
    </nav>
  )
}
```

## Form Handling

```jsx
import { useForm } from '@inertiajs/react'

function CreateProject() {
  const { data, setData, post, processing, errors } = useForm({
    name: '',
    description: ''
  })

  function handleSubmit(e) {
    e.preventDefault()
    post('/projects')
  }

  return (
    <form onSubmit={handleSubmit}>
      <input
        value={data.name}
        onChange={e => setData('name', e.target.value)}
      />
      {errors.name && <span className="error">{errors.name}</span>}
      <button type="submit" disabled={processing}>Create</button>
    </form>
  )
}
```

## App Data Access

For app config (NOT user-specific data):
```jsx
// Access global app data
const appData = window.App?.data()
const appName = appData?.name

// For auth state
const user = window.Auth?.user()
const isAuthenticated = window.Auth?.isAuthenticated()
```

**Note:** Prefer props for page-specific data. Use globals only for app-wide config.

## Quick Reference

| Do | Don't |
|----|-------|
| Props from controller | Fetch data client-side |
| `layout 'inertia'` in controller | Mix with ERB layout |
| Destructured props | Unstructured props object |
| `useForm` for forms | Manual form state |
| `Link` for navigation | `<a>` tags (breaks SPA) |

## Colors

This app uses a **semantic color system** — the default Tailwind palette is disabled. Only semantic names produce styling:

- **Backgrounds:** `bg-background`, `bg-surface-0` through `bg-surface-3`, `bg-muted`, `bg-card`
- **Text:** `text-foreground`, `text-muted-foreground`
- **Brand:** `bg-primary`, `text-primary`, `bg-secondary`, `bg-accent`
- **Status:** `text-destructive`, `text-success`, `text-warning`, `text-info`
- **Popovers:** `bg-popover`, `text-popover-foreground` (dropdowns, modals, tooltips)
- **Borders:** `border-border`, `border-input`, `ring-ring`
- **Charts:** `bg-chart-1` through `bg-chart-5`
- **Opacity:** `bg-primary/10`, `text-foreground/60`
- **Gradients:** `from-primary to-accent`, `from-surface-0 to-surface-1`

NEVER use `gray-*`, `blue-*`, `red-*`, `slate-*`, etc. — they are disabled and render nothing. See `AGENTS.md` for the full palette reference.

## Common Mistakes

1. **Fetching data that's in props** - Check controller first
2. **Wrong layout** - Inertia controllers need `layout 'inertia'`
3. **Using ERB-only globals** - Some window vars only exist in application.html.erb
4. **Breaking SPA navigation** - Always use Inertia `Link`, not `<a>`
5. **Not handling loading states** - Check `processing` in forms