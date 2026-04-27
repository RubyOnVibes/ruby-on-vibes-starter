# Tailwind CSS

## Dark Mode

This template uses **class-based dark mode**, not the Tailwind v4 default (media query).

### Configuration

In `app/assets/tailwind/vibes_theme.css` (and duplicated in the CDN `<style type="text/tailwindcss">` block):
```css
@custom-variant dark (&:is(.dark *));
```

This means `dark:` utilities only apply when a `.dark` class exists on an ancestor element (typically `<html>`).

### How It Works

1. Theme is stored in `localStorage.getItem('theme')`
2. On page load, JS adds `.dark` to `<html>` if `theme === 'dark'`
3. Users toggle via the navbar theme button
4. **System preference is NOT auto-detected** - users must manually toggle

### Why Class-Based?

1. **Centralized theming** - `_vibes_theme.html.erb` defines CSS variables for both light and dark modes using `html.dark` selectors
2. **Custom styles** - Many views have manual `html.dark .class-name` rules that depend on this pattern
3. **User control** - Explicit theme choice persists across sessions

### Tailwind Play Difference

Tailwind Play uses `@media (prefers-color-scheme: dark)` by default. If you test `dark:bg-white` there, it auto-switches with your OS. That won't happen here - use the theme toggle or set `localStorage.setItem('theme', 'dark')`.

### Adding System Preference Detection

If you want dark mode to follow OS preference for new users, update the theme init script in both layouts:

```javascript
const stored = localStorage.getItem('theme');
const prefersDark = window.matchMedia('(prefers-color-scheme: dark)').matches;
if (stored === 'dark' || (stored !== 'light' && prefersDark)) {
  document.documentElement.classList.add('dark');
}
```
