---
name: navbar-conventions
description: Conventions for editing navbar components
---

# Navbar Conventions

The navbar uses a **hybrid ERB + small React islands** pattern for optimal stability.

## Architecture

```
_navbar.html.erb (ERB pages)          NavbarCore.jsx (Inertia pages)
    │                                      │
    ├── Logo mark + app name  ←──SYNC──→  ├── Logo mark + app name
    ├── Back arrow                         ├── Back arrow
    ├── Theme toggle                       ├── Theme toggle
    ├── NotificationsIconIsland            ├── NotificationBellWithDropdown
    └── UserMenuDropdownIsland             └── UserMenuDropdown
```

**CRITICAL**: The logo/branding section must be IDENTICAL in both navbars.

## Why Small Islands?

1. **Stable layout**: The `<nav>` is server-rendered ERB - no hydration timing issues
2. **Simple placeholders**: Each island only needs to match a single button
3. **Shared components**: Interactive parts (dropdowns) are single source of truth
4. **No React overhead for simple things**: Theme toggle is pure JS

## Files

| File | Purpose |
|------|---------|
| `app/views/application/_navbar.html.erb` | ERB navbar for ERB pages |
| `app/javascript/components/navbar/NavbarCore.jsx` | Navbar component for Inertia pages |
| `app/javascript/islands/components/NotificationsIconIsland.jsx` | Island wrapper → NotificationBellWithDropdown |
| `app/javascript/islands/components/UserMenuDropdownIsland.jsx` | Island wrapper → UserMenuDropdown |
| `app/javascript/components/notifications/NotificationBellWithDropdown.jsx` | Shared notification component |
| `app/javascript/components/user/UserMenuDropdown.jsx` | Shared user menu component |

## Logo/Branding Sync (CRITICAL)

The logo section must be **IDENTICAL** in both `_navbar.html.erb` and `NavbarCore.jsx`.

**Current pattern** (logo mark + app name):

ERB:
```erb
<%= link_to root_path, class: "flex items-center gap-3 group" do %>
  <div class="w-9 h-9 rounded-xl bg-primary flex items-center justify-center shadow-sm group-hover:shadow transition-shadow">
    <span class="text-sm font-semibold text-primary-foreground tracking-tight">
      <%= RubyOnVibes.application_name.first.upcase %>
    </span>
  </div>
  <span class="text-xl font-semibold text-foreground group-hover:text-primary transition-colors">
    <%= RubyOnVibes.application_name %>
  </span>
<% end %>
```

React (NavbarCore.jsx):
```jsx
<a href="/" className="flex items-center gap-3 group">
  <div className="w-9 h-9 rounded-xl bg-primary flex items-center justify-center shadow-sm group-hover:shadow transition-shadow">
    <span className="text-sm font-semibold text-primary-foreground tracking-tight">
      {appData?.name?.charAt(0)?.toUpperCase() || ''}
    </span>
  </div>
  <span className="text-xl font-semibold text-foreground group-hover:text-primary transition-colors">
    {appData?.name || ''}
  </span>
</a>
```

**When editing the logo**:
1. Edit BOTH files
2. Keep classes identical
3. ERB uses `RubyOnVibes.application_name`, React uses `appData?.name`

## Rules

### SVG Sizing
Always include explicit `width` and `height` attributes on SVGs matching the viewBox dimensions (e.g., `viewBox="0 0 24 24" width="24" height="24"`). This prevents SVGs from rendering at full viewport size before Tailwind CSS loads in CDN mode.

### When editing _navbar.html.erb

This is the **layout source of truth** for ERB pages. It contains:
- Static elements (back arrow, theme toggle)
- `react_component` calls for interactive islands
- **Placeholders that must match React's initial render**

### Placeholder Requirements

Each `react_component` block must render HTML that EXACTLY matches what React renders initially:

```erb
<%# Notifications - matches NotificationBellWithDropdown's outer structure %>
<%= react_component('NotificationsIconIsland') do %>
  <div class="relative">
    <button class="relative p-2 rounded-lg bg-surface-1 hover:bg-surface-2 text-foreground transition-colors" aria-label="Notifications">
      <svg>...bell icon...</svg>
    </button>
  </div>
<% end %>
```

Key points:
- Same wrapper div (`<div class="relative">`)
- Same button classes
- Same icon
- Dropdown is NOT in placeholder (it's hidden initially)

### When editing shared components

Changes to `NotificationBellWithDropdown` or `UserMenuDropdown` affect:
- ERB pages (via islands)
- Inertia pages (direct usage)

**If you change the initial render structure**, update the corresponding placeholder in `_navbar.html.erb`.

### Theme Toggle

The theme toggle is pure vanilla JS (not React). Edit it directly in `_navbar.html.erb`.

## Adding Nav Items

Nav items (Chat, Workspaces) are config-driven via `vibes_helper.rb`:

```ruby
def nav_menu_items
  items = []
  items << { key: "chat", label: "Chat", path: "/c", icon: "MessageSquare" } if RubyOnVibes.chat?
  items << { key: "workspaces", label: "Workspaces", path: "/ws", icon: "Workspace" } if RubyOnVibes.teams?
  items
end
```

These are read by `UserMenuDropdown` via `window.App.data().navItems`.

## Quick Checklist

When editing navbar:
- [ ] **Logo changes**: Edit BOTH `_navbar.html.erb` AND `NavbarCore.jsx`
- [ ] Logo classes are identical in both files
- [ ] ERB placeholder matches React's initial render (for islands)
- [ ] Same wrapper structure (`<div class="relative">`)
- [ ] Same classes on buttons
- [ ] Same icons/SVGs
- [ ] Dropdown content NOT in placeholder (hidden initially)
