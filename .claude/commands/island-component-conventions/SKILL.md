---
name: island-component-conventions
description: Use when creating or modifying IslandJS React components in app/javascript/islands
---

# Island Component Conventions

## Stack Context

- **IslandJS Rails gem** embeds React "islands" in ERB pages
- Components live in `app/javascript/islands/components/`
- The `react_component` ERB helper generates the container div, data attributes, AND mount/unmount JavaScript
- Data flows: ERB → `data-initial-state` attribute → `useTurboProps(containerId)` in the component
- Works with Turbo navigation (not full SPA)

## CRITICAL: Always Use the `react_component` Helper

**NEVER hand-write island markup in ERB.** The helper generates everything: container div, data-initial-state, mount script, unmount script, Turbo lifecycle hooks.

```erb
<%# CORRECT — always use the helper %>
<%= react_component('TickerTapeIsland', { items: @items }) %>

<%# WRONG — will never mount %>
<div data-island="TickerTapeIsland"></div>
<div data-component="TickerTapeIsland"></div>
```

## Three Steps to Add a New Island

### Step 1: Create the Component

```jsx
// app/javascript/islands/components/TickerTapeIsland.jsx
import React, { useState, useEffect } from 'react';
import { useTurboProps, useTurboCache } from '../utils/turbo';

function TickerTapeIsland({ containerId }) {
  const initialProps = useTurboProps(containerId);
  const [items, setItems] = useState(initialProps.items || []);

  useEffect(() => {
    const cleanup = useTurboCache(containerId, { items }, true);
    return cleanup;
  }, [containerId, items]);

  return (
    <div className="flex gap-4 overflow-x-auto">
      {items.map((item, i) => (
        <span key={i} className="text-foreground whitespace-nowrap">{item}</span>
      ))}
    </div>
  );
}

export default TickerTapeIsland;
```

**Key patterns:**
- `{ containerId }` is the **only prop** the component receives from the mount script
- `useTurboProps(containerId)` reads the actual data from `data-initial-state`
- `useTurboCache` persists state back for Turbo's page cache — it returns a cleanup function (NOT `[state, setState]` like `useState`)
- Import turbo utilities from `'../utils/turbo'` (there is no `'islandjs-rails'` JS package)

### Step 2: Register in Entrypoint

```js
// app/javascript/entrypoints/islands.js — add import and export
import TickerTapeIsland from '../islands/components/TickerTapeIsland.jsx'

window.islandjsRails = {
  // ...existing components...
  TickerTapeIsland,
}
```

There is no `registerComponents()` function. Registration is simply adding to the `window.islandjsRails` object in `entrypoints/islands.js`.

### Step 3: Render in ERB with `react_component`

```erb
<%= react_component('TickerTapeIsland', { items: @ticker_items }) %>
```

## `react_component` Helper API

```ruby
react_component(component_name, props = {}, options = {}, &block)
```

- **component_name** — String matching the key in `window.islandjsRails`
- **props** — Flat hash of data (stored in `data-initial-state`, read via `useTurboProps`)
- **options** — Container/script options: `container_id:`, `class:`, `tag:`, `namespace:`, `placeholder_class:`, `placeholder_style:`
- **block** — Placeholder HTML shown until React mounts

### Placeholders: Match the React Render

Use the block form to provide placeholder HTML that **visually matches what React will render**. This prevents layout shift and ensures a seamless transition when React mounts.

```erb
<%# Placeholder mirrors what NotificationsIconIsland will render %>
<%= react_component('NotificationsIconIsland') do %>
  <div class="relative">
    <button class="relative p-2 rounded-lg bg-surface-1 text-foreground">
      <svg class="w-5 h-5" fill="none" viewBox="0 0 24 24" stroke="currentColor">
        <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M15 17h5l-1.405-1.405..." />
      </svg>
    </button>
  </div>
<% end %>
```

### Real Examples from This App

```erb
<%# Simple props, no placeholder needed %>
<%= react_component('ToastIsland', { flash: flash.to_hash }) %>

<%# Props from Rails, with placeholder block %>
<%= react_component('UserMenuDropdownIsland', {
  avatarUrl: current_user.avatar.attached? ? url_for(current_user.avatar) : nil,
  initials: current_user.first_name&.first&.upcase || "?",
}) do %>
  <button class="flex items-center gap-2 p-1 rounded-lg"><%# placeholder %></button>
<% end %>

<%# Custom container_id (needed when component reads from a sibling data div) %>
<%= react_component "ChatIsland", { containerId: "chat-panel-container" }, {
  container_id: "chat-panel-container"
} %>

<%# In a loop — each instance needs a unique container_id %>
<% @chats.each do |chat_item| %>
  <%= react_component "ChatSidebarIsland", {
    containerId: "chat-sidebar-item-#{chat_item.to_param}"
  }, { container_id: "chat-sidebar-item-#{chat_item.to_param}" } %>
<% end %>
```

## Turbo Utilities (`../utils/turbo`)

| Function | Purpose |
|----------|---------|
| `useTurboProps(containerId)` | Reads initial props from `data-initial-state`. Returns `{}` if not found. |
| `useTurboCache(containerId, state, autoRestore)` | Persists state back to `data-initial-state` for Turbo cache. Returns cleanup function. Call in `useEffect`. |
| `persistState(containerId, state)` | Manual one-shot state persistence. |

## Colors

Semantic color system — default Tailwind palette is disabled. Only these work:

- **Backgrounds:** `bg-background`, `bg-surface-0` through `bg-surface-3`, `bg-muted`, `bg-card`
- **Text:** `text-foreground`, `text-muted-foreground`
- **Brand:** `bg-primary`, `text-primary`, `bg-secondary`, `bg-accent`
- **Status:** `text-destructive`, `text-success`, `text-warning`, `text-info`
- **Popovers:** `bg-popover`, `text-popover-foreground`
- **Borders:** `border-border`, `border-input`, `ring-ring`

**NEVER** use `gray-*`, `blue-*`, `red-*`, `slate-*`, etc. — they render nothing.

## Common Mistakes

| Mistake | Fix |
|---------|-----|
| Hand-writing `<div data-island="...">` in ERB | Always use `<%= react_component('Name', { props }) %>` |
| `import from 'islandjs-rails'` | Import from `'../utils/turbo'` |
| `registerComponents({ ... })` | Set `window.islandjsRails = { ... }` in `entrypoints/islands.js` |
| Destructuring ERB props in component args | Only `{ containerId }` is passed; use `useTurboProps(containerId)` for data |
| Using `useTurboCache` like `useState` | It returns a cleanup function, not `[state, setState]` |
| No placeholder block | Provide ERB block matching the React render to prevent layout shift |
| SVG without `width`/`height` attributes | Always add explicit `width` and `height` matching the `viewBox` (e.g., `viewBox="0 0 24 24" width="24" height="24"`) to prevent full-viewport rendering before CSS loads |
| Forgetting to register component | Add to `window.islandjsRails` in `entrypoints/islands.js` |
