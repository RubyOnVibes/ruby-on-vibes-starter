---
name: shared-component-conventions
description: Conventions for shared React components used by both Inertia and ERB islands
---

# Shared Component Conventions

Components in `app/javascript/components/` are **shared** - used by both Inertia pages AND ERB islands.

## How Bundling Works

| Bundle | External (CDN) | Bundled |
|--------|----------------|---------|
| `islands_bundle.js` | `react`, `react-dom` only | Everything else (sonner, etc.) |
| Inertia (vite) | Nothing | Everything |

**Key insight:** npm packages like `sonner` ARE bundled into the islands bundle. They work fine.

## The Real Constraint: Inertia Runtime Context

```jsx
// ✗ FORBIDDEN - requires Inertia runtime context
import { usePage, router, Link } from '@inertiajs/react'

// usePage() needs Inertia to have rendered the page
// router needs Inertia's navigation system
// These don't exist when React hydrates an island in ERB
```

This is NOT a bundling issue - `@inertiajs/react` could be bundled, but the APIs require Inertia to be managing the page.

## What Works in Shared Components

```jsx
// ✓ React (external in islands, bundled in Inertia - both work)
import { useState, useEffect, useRef } from 'react'

// ✓ npm packages (bundled into both islands and Inertia)
import { toast, Toaster } from 'sonner'  // Currently used in ToastIsland

// ✓ Other shared components
import { UserMenuDropdown } from '../user'

// ✓ Browser APIs
fetch('/api/endpoint')
localStorage.getItem('key')
document.querySelector('meta[name="csrf-token"]')
```

## What Does NOT Work

```jsx
// ✗ Inertia APIs - require Inertia runtime context
import { usePage } from '@inertiajs/react'  // No Inertia context in islands
import { router } from '@inertiajs/react'   // No Inertia router in islands
import { Link } from '@inertiajs/react'      // Inertia navigation component
```

## Directory Structure

```
app/javascript/
├── components/        ← SHARED (no @inertiajs/react)
│   ├── notifications/ NotificationBellWithDropdown, NotificationBell, etc.
│   ├── user/          UserMenuDropdown
│   └── chat/          Chat components
│
├── islands/           ← ERB adapters (read window.*, wrap shared components)
│   └── components/
│       ├── ToastIsland.jsx
│       ├── NotificationsIconIsland.jsx  → wraps NotificationBellWithDropdown
│       ├── UserMenuDropdownIsland.jsx   → wraps UserMenuDropdown
│       └── ...
│
└── pages/             ← Inertia-only (CAN use @inertiajs/react)
    └── components/
        └── ToasterProvider.jsx  Uses usePage() for flash
```

## Getting Data: Islands vs Inertia

The same component may need data from different sources:

| Context | How to get user data | How to get flash messages |
|---------|---------------------|--------------------------|
| Islands | `window.Auth.user()` | Props from ERB |
| Inertia | Props from page | `usePage().props.flash` |

That's why we have thin wrappers:
- `NotificationsIconIsland.jsx` wraps `NotificationBellWithDropdown`
- `UserMenuDropdownIsland.jsx` reads props, passes to `UserMenuDropdown`

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

## Quick Checklist

- [ ] No `@inertiajs/react` imports (usePage, router, Link)
- [ ] Component gets data via props (not Inertia context)
- [ ] If used in ERB, has a corresponding island wrapper

## Examples

### Good: Shared component using npm package

```jsx
// components/notifications/NotificationBellWithDropdown.jsx
import { useState, useEffect } from 'react'
import NotificationBell from './NotificationBell'
import NotificationDropdown from './NotificationDropdown'

// Works in both contexts - gets data via fetch, not Inertia
export default function NotificationBellWithDropdown({ initialUnreadCount = 0 }) {
  const [notifications, setNotifications] = useState([])

  const fetchNotifications = async () => {
    const response = await fetch('/notifications.json')
    // ...
  }
}
```

### Good: Context-specific wrappers

```jsx
// islands/components/ToastIsland.jsx - ERB version
import { toast, Toaster } from 'sonner'
import { useTurboProps } from '../utils/turbo'

export default function ToastIsland({ containerId }) {
  const { flash } = useTurboProps(containerId)  // Data from ERB props
  // Show toasts based on flash...
}

// pages/components/ToasterProvider.jsx - Inertia version
import { toast, Toaster } from 'sonner'
import { usePage } from '@inertiajs/react'

export default function ToasterProvider() {
  const { props } = usePage()  // Data from Inertia context
  const flash = props.flash
  // Show toasts based on flash...
}
```

Both use `sonner` for toasts, but get flash data differently.