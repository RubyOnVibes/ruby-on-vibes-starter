# Email Styling Guide

## Philosophy

Email clients have **terrible** CSS support. To ensure reliable delivery and rendering across Gmail, Outlook, Apple Mail, and mobile clients, we use:

1. **Hardcoded RGB values** (no CSS variables - they don't work in most clients)
2. **Inline styles** for critical styling (via helper methods)
3. **`<style>` tags** for general typography/resets only
4. **Email-safe fonts** (system font stacks)

## Single Source of Truth

**All colors** (web + email) come from the `vibes_tokens` helper in `app/helpers/vibes_helper.rb`:

```ruby
# Edit app/helpers/vibes_helper.rb to customize your brand
def vibes_tokens
  {
    brand: "255 0 0",           # Your primary brand color (RGB)
    brand_contrast: "255 255 255",
    text_1: "15 23 42",
    surface_0: "252 252 253",
    # ... etc
  }
end
```

This single source is used by:
- **Web**: `_vibes_theme.html.erb` generates CSS variables from it
- **Email**: `_vibes_email_theme.html.erb` generates inline styles from it

**To customize your brand colors:** Edit the `vibes_tokens` method in `app/helpers/vibes_helper.rb`. Both web and email will update automatically.

## Files

- **`app/views/application/_vibes_email_theme.html.erb`** - Email-safe theme (NO CSS variables)
- **`app/views/layouts/mailer.html.erb`** - HTML email layout with branding header & footer
- **`app/views/layouts/mailer.text.erb`** - Plain text email layout

## Creating Buttons in Emails

**❌ WRONG** (CSS classes don't work reliably):
```erb
<%= link_to "Click Me", url, class: "btn btn-primary" %>
```

**✅ RIGHT** (inline styles via helper):
```erb
<%= link_to "Click Me", url, style: email_button_style(:primary) %>
```

Available button variants:
- `:primary` - Brand color button
- `:secondary` - Subtle secondary button

**Key principles:**
- Use inline styles for everything (no CSS classes for critical elements)
- Access colors via `vibes_tokens[:color_name]`
- Use `email_button_style(:primary)` for buttons
- Keep it minimal - lots of whitespace, clean typography

## What Works / Doesn't Work

### ✅ Works Everywhere
- Inline styles
- Tables for layout
- Basic HTML: `<p>`, `<h1>`, `<a>`, `<strong>`, `<br>`
- RGB colors: `rgb(30 64 175)`
- System fonts

### ❌ Don't Use
- CSS variables: `var(--color-primary)`
- Flexbox/Grid
- `<div>` for layout (use `<table>` instead)
- Custom web fonts (unreliable loading)
- JavaScript (stripped by all clients)
- Background images on `<div>` (use `<table>` + `<td background="">` for Outlook)