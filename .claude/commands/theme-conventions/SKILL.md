---
name: theme-conventions
description: Use when editing theme infrastructure files (_vibes_theme.html.erb, vibes_theme.css)
---

# Theme Extension Guide

This skill is for **extending** the theme system (adding new semantic colors). For **using** existing colors, see `docs/ada.md` — it has the full palette reference.

## Extending the Theme

When the user needs a new semantic color (e.g., `highlight`), touch 3 files:

### File 1: `app/helpers/vibes_helper.rb` — token values

**Format: space-separated RGB triplets** (e.g., `"255 200 0"`). NOT hex, NOT comma-separated, NOT `rgb(...)`.

```ruby
def vibes_tokens
  { ..., highlight: "255 200 0" }    # ✓ space-separated RGB
  # NOT: "#FFD700", "255,200,0", "rgb(255 200 0)"
end

def vibes_tokens_dark
  { ..., highlight: "255 220 50" }
end
```

### File 2: `app/views/application/_vibes_theme.html.erb` — CSS variables

Add the primitive in `:root` (light), next to the other `--vibes-*` entries:
```css
--vibes-highlight: rgb(<%= tokens[:highlight] %>);
```

Add the primitive in `html.dark` (dark), next to the other dark overrides:
```css
--vibes-highlight: rgb(<%= dark_tokens[:highlight] %>);
```

Add the semantic mapping in `:root`, next to the other `--color-*` entries:
```css
--color-highlight: var(--vibes-highlight);
```

### File 3: `app/assets/tailwind/vibes_theme.css` — Tailwind registration

Add inside `@theme inline { }`:
```css
--color-highlight: var(--vibes-highlight);
```

The CDN mode auto-includes this file — no separate CDN step needed.

Now `bg-highlight`, `text-highlight`, `border-highlight/50`, `from-highlight`, etc. all work automatically — including dark mode auto-switching and opacity modifiers.

## When to Extend vs. Escape Hatch

| Scenario | Approach |
|----------|----------|
| Color appears in multiple places / should respond to theme | **Extend** — add a new token |
| One-off brand color, specific logo, single decorative element | **Escape hatch** — `bg-[#hex]` |
| Chart with >5 series | **Extend** — add `chart-6`, `chart-7`, etc. |

## Dark Mode Behavior

- Semantic colors auto-switch via CSS variable cascade — no `dark:` prefix needed for colors
- Status colors (`info`, `warning`, `success`) inherit light values in dark mode by default
- Override in `vibes_tokens_dark` only if your new color needs a different dark variant
- Only use `dark:` for non-color properties that differ between modes

## Component Classes

Defined in `_vibes_theme.html.erb`. **NEVER invent new `v-*` classes:**

```html
<button class="btn btn-primary">      <!-- brand button -->
<button class="btn btn-secondary">    <!-- subtle button -->
<button class="btn btn-destructive">  <!-- danger button -->
<button class="btn btn-ghost">        <!-- transparent button -->
<a class="v-link">                    <!-- brand-colored link -->
<a class="v-link-muted">              <!-- muted link, foreground on hover -->
```

## Quick Checklist (for theme infrastructure edits)

- [ ] Token format is space-separated RGB triplets (`"255 200 0"`)
- [ ] Primitive added to both `:root` and `html.dark` sections
- [ ] Semantic mapping added to `:root` in `_vibes_theme.html.erb`
- [ ] Same semantic mapping added to `@theme inline` in `vibes_theme.css`
- [ ] No invented `v-*` classes — use existing ones or Tailwind utilities

## Common Mistakes

1. **Wrong token format** — Must be `"255 200 0"` (space-separated), not hex or comma-separated
2. **Forgetting `vibes_theme.css`** — CDN auto-includes it, but build mode also needs the `@theme` line
3. **Forgetting dark mode primitive** — Add to `html.dark` block even if value is same as light
4. **Inventing `v-custom-class`** — Use Tailwind utilities or existing component classes
