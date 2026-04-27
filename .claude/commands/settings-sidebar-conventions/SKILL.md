---
name: settings-sidebar-conventions
description: Conventions for editing settings sidebar components
---

# Settings Sidebar Conventions

The settings sidebar uses a **hybrid ERB + React island** pattern with a `*Core` component architecture.

## Architecture

```
vibes_helper.rb (settings_nav_items) <- Single source of truth for links
         |
         v
   window.App.data().settingsNavItems <- Exposed to JS via body data attribute
         |
  +------+---------------------------+
  |                                  |
  v                                  v
_sidebar_nav.html.erb          SettingsSidebarCore.jsx (shared UI)
  |                                  ^
  v                                  |
SettingsSidebarIsland.jsx ------+   |
  (hydrates over ERB)               |
                                    |
                            SettingsSidebar.jsx (Inertia wrapper)
                                    |
                                    v
                            SettingsLayout.jsx (Inertia pages)
```

## The *Core Pattern

This follows the same pattern as `NavbarCore` / `Navbar`:

| Component | Purpose | Used By |
|-----------|---------|---------|
| `SettingsSidebarCore.jsx` | Core UI implementation | Island + Wrapper |
| `SettingsSidebar.jsx` | Thin Inertia wrapper | SettingsLayout |
| `SettingsSidebarIsland.jsx` | Island wrapper for ERB | _sidebar_nav.html.erb |

**Rule**: Visual/behavior changes go in `*Core`. Wrappers only handle props transformation.

## Files

| File | Purpose |
|------|---------|
| `app/helpers/vibes_helper.rb` | `settings_nav_items` - nav items source of truth |
| `app/views/application/_sidebar_nav.html.erb` | ERB nav with React island placeholder |
| `app/javascript/components/settings/SettingsSidebarCore.jsx` | **Core UI component** |
| `app/javascript/components/settings/SettingsSidebar.jsx` | Inertia wrapper |
| `app/javascript/islands/components/SettingsSidebarIsland.jsx` | Island wrapper for ERB |
| `app/javascript/layouts/SettingsLayout.jsx` | Inertia layout with settings sidebar |

## Data Flow

All components read from window globals - no props needed:

- **Nav items**: `window.App.data().settingsNavItems`
- **User data**: `window.Auth.user()`
- **Current path**: `window.location.pathname`

## Rules

### When adding/removing nav items

Edit `settings_nav_items` in `vibes_helper.rb` - this is the **single source of truth**.
Both ERB (via helper) and React (via `window.App.data().settingsNavItems`) read from here.

```ruby
def settings_nav_items
  items = []
  items << { key: "dashboard", label: "Dashboard", path: "/dashboard" } if RubyOnVibes.dashboard?
  items << { key: "profile", label: "Profile", path: edit_profile_registration_path }
  # ... add new items here
  items
end
```

### When editing visual design or behavior

Edit `SettingsSidebarCore.jsx` - this is the **single source of truth** for the React UI.

Both wrappers (`SettingsSidebar.jsx` and `SettingsSidebarIsland.jsx`) simply render the Core:

```jsx
// SettingsSidebarIsland.jsx
import { SettingsSidebarCore } from '../../components/settings'
export default function SettingsSidebarIsland() {
  return <SettingsSidebarCore />
}

// SettingsSidebar.jsx (Inertia wrapper)
import SettingsSidebarCore from './SettingsSidebarCore'
export function SettingsSidebar({ navItems, currentPath }) {
  return <SettingsSidebarCore navItems={navItems} currentPath={currentPath} />
}
```

### ERB placeholder sync

The ERB placeholder in `_sidebar_nav.html.erb` must **EXACTLY match** React's initial render to avoid hydration flicker.

**Mobile dropdown button:**
```html
<!-- ERB -->
<button type="button"
        class="w-full flex items-center justify-between px-4 sm:px-6 py-3 transition-colors cursor-pointer border-b border-transparent hover:bg-surface-1">

<!-- React (SettingsSidebarCore.jsx) -->
<button
  onClick={() => setIsOpen(!isOpen)}
  type="button"
  className={`w-full flex items-center justify-between px-4 sm:px-6 py-3 transition-colors cursor-pointer border-b ${
    isOpen ? 'bg-surface-1 border-border' : 'border-transparent hover:bg-surface-1'
  }`}
>
```

**Desktop nav links:**
```
ERB:    "block no-underline px-4 py-3 rounded-lg text-sm font-medium transition-all"
React:  "block no-underline px-4 py-3 rounded-lg text-sm font-medium transition-all"
```

**Active/inactive classes:**
```
Active:   "bg-surface-2 text-foreground"
Inactive: "text-muted-foreground hover:bg-surface-1 hover:text-foreground"
```

### Using in Inertia pages

For Inertia pages that need the settings sidebar, use `SettingsLayout`:

```jsx
import SettingsLayout from '../layouts/SettingsLayout'

export default function MySettingsPage() {
  return (
    <SettingsLayout>
      <h1>My Settings</h1>
      {/* Page content */}
    </SettingsLayout>
  )
}

// To hide the settings sidebar on a specific page:
export default function FullWidthPage() {
  return (
    <SettingsLayout hideSettingsSidebar>
      <h1>Full Width Content</h1>
    </SettingsLayout>
  )
}
```

## Quick Checklist

When editing settings sidebar:
- [ ] If adding/removing links: Edit `settings_nav_items` in `vibes_helper.rb`
- [ ] If changing UI/behavior: Edit `SettingsSidebarCore.jsx` (NOT the wrappers)
- [ ] If changing ERB placeholder: Ensure it matches Core's initial render exactly
- [ ] Same wrapper structure (`<div class="lg:hidden -mx-4 sm:-mx-6">` for mobile)
- [ ] Same classes on mobile dropdown button
- [ ] Same classes on desktop nav links (`"block no-underline px-4 py-3 rounded-lg..."`)
- [ ] Same active/inactive class names
- [ ] Wrappers only pass props through, never add UI logic
