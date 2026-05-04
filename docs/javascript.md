# JavaScript Usage

This template supports multiple JavaScript approaches, each suited for different complexity levels.

## Quick Recommendation

| Complexity | Recommended Approach |
|------------|---------------------|
| Simple toggles, dropdowns, tabs | **Alpine.js** |
| React components in ERB views | **IslandJS Rails** |
| Full SPA pages with React | **Inertia.js** |

## Alpine.js (Recommended for Simple Interactivity)

Loaded from CDN with production-grade Turbo compatibility via official Alpine plugin API. Automatically handles full page navigation, Turbo Frames, and Turbo Streams with proper component lifecycle management.

```erb
<div x-data="{ open: false }">
  <button @click="open = !open">Toggle</button>
  <div x-show="open">Content</div>
</div>
```

No build step. No configuration. Just works.

**Integration details:**
- Uses Alpine.plugin() for proper framework integration
- Calls Alpine.destroyTree() + Alpine.initTree() for cleanup and re-initialization
- Handles turbo:load, turbo:frame-load, and turbo:before-stream-render separately
- Proper error handling and timing with queueMicrotask

**Example usage:** See `AGENTS.md` → "Alpine.js" section and `app/views/devise/sessions/new.html.erb` for a password toggle example.

## IslandJS Rails (React Components in ERB)

For reactive components that need to live inside traditional ERB views.

```erb
<%= react_component('MyComponent', { userId: current_user.id }) %>
```

Components live in `app/javascript/islands/components/`. Supports Turbo cache persistence via `useTurboCache`. See [islandjs-rails README](https://github.com/Praxis-Emergent/islandjs-rails) for full docs.

**Dev:** `yarn watch:islands`
**Build:** `yarn build:islands`

## Inertia.js (Full SPA Pages)

For complex pages that benefit from full React with server-side rendering.

Pages live in `app/javascript/pages/`. Controllers render via:

```ruby
render inertia: 'MyPage', props: { user: current_user }
```

**Build:** `bin/vite build --ssr`

## Summary

```
Alpine.js   → x-data, @click, x-show (zero config, recommended)
IslandJS    → react_component helper (Turbo compatible React)
Inertia.js  → render inertia: 'Page' (full SPA with SSR)
```