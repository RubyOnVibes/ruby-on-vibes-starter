# Server-Side Rendering (SSR)

**Status:** Production Ready - Auto-restart, hot-reload enabled

Ruby on Vibes includes battle-tested SSR for Inertia.js pages with zero-config setup.

---

## ⚠️ First-Time Setup (Important!)

You need **ONE manual restart** to enable the SSR supervisor and hot reload:

```bash
fly apps restart YOUR_APP_NAME
```

**After this initial restart:**
- ✅ SSR automatically restarts on code changes
- ✅ No more manual restarts needed
- ✅ Hot reload works in ~1.5s

**Why?** The SSR supervisor loop is part of `bin/vibes-server`, which only starts when the container restarts. Once running, it handles all future SSR updates automatically.

---

## Architecture

### Development
- SSR dev server via `bin/dev` (Procfile: `ssr: bin/vite ssr`)
- Hot module reload enabled
- Port 13714 (localhost)

### Production
- SSR bundle built in Docker image (`bin/vite build --ssr`)
- SSR runs via `bin/vibes-server` supervisor
- Auto-restart on crash or code changes
- Single-machine architecture (Rails + SSR share localhost)

### Request Flow
```
Browser → Rails Controller
    ↓
Inertia forwards page data → SSR Server (localhost:13714)
    ↓
SSR renders React to HTML string
    ↓
Rails injects HTML + data → Browser
    ↓
React hydrates → Interactive
```

---

## Critical Gotchas

### Browser API Guards

**❌ WRONG - Will crash SSR:**
```jsx
const theme = localStorage.getItem('theme')  // SSR has no localStorage
const width = window.innerWidth              // SSR has no window
```

**✅ CORRECT - SSR-safe:**
```jsx
useEffect(() => {
  if (typeof window === 'undefined') return  // Skip on server
  const theme = localStorage.getItem('theme')
}, [])
```

**APIs requiring guards:**
- `localStorage` / `sessionStorage`
- `window.*` (all window methods)
- `document.*` (all document methods)
- `navigator.*`
- Third-party libs that access DOM

---

### Default State on Server

**Theme Example:**
```jsx
// ❌ BAD: No default, crashes SSR
const [theme, setTheme] = useState()

// ✅ GOOD: Safe default for SSR
const [theme, setTheme] = useState('light')

useEffect(() => {
  if (typeof window === 'undefined') return
  setTheme(localStorage.getItem('theme') || 'light')
}, [])
```

**Key principle:** Always provide SSR-safe defaults, hydrate in `useEffect`.

---

### Third-Party Libraries

**Some libs assume browser environment:**
```jsx
import Analytics from 'analytics-lib'  // Might crash SSR
```

**Solutions:**

**1. Dynamic import:**
```jsx
useEffect(() => {
  import('analytics-lib').then(({ Analytics }) => {
    // Use Analytics
  })
}, [])
```

**2. Conditional render:**
```jsx
const [isClient, setIsClient] = useState(false)

useEffect(() => {
  setIsClient(true)
}, [])

return isClient ? <AnalyticsWidget /> : null
```

**3. Add to vite.config.js externals** (if causes build issues)

---

## Production Checklist

### Before Deploy
- [ ] All browser APIs guarded with `typeof window === 'undefined'`
- [ ] All state has SSR-safe defaults
- [ ] Third-party libs are SSR-compatible
- [ ] `inertia_ssr_head` in layout (`app/views/layouts/inertia.html.erb`)
- [ ] Test locally: `curl http://localhost:3001 | grep '<div id="app"'`

### After Deploy
- [ ] Check SSR rendered content: `curl https://your-app.fly.dev`
- [ ] Verify no SSR errors in logs: `fly logs | grep SSR`
- [ ] Confirm page source has HTML (not empty `<div id="app">`)

---

## Configuration

**Enable SSR** (already enabled in templates):
```ruby
# config/initializers/inertia_rails.rb
InertiaRails.configure do |config|
  config.ssr_enabled = ViteRuby.config.ssr_build_enabled
  config.ssr_url = 'http://localhost:13714'  # Default, no need to set
end
```

**Disable per-page:**
```ruby
class AdminController < ApplicationController
  inertia_config ssr_enabled: false  # Skip SSR for admin
end
```

---

## Debugging

### Check SSR Status
```bash
# Is SSR server running?
curl http://localhost:13714
# Should return: {"status":"NOT_FOUND",...}

# On Fly.io
fly ssh console -a YOUR_APP -C "curl http://localhost:13714"
```

### View SSR Logs
```bash
# Local
tail -f log/development.log | grep SSR

# Fly.io
fly logs -a YOUR_APP | grep SSR
```

### Common Errors

**1. `ReferenceError: window is not defined`**
```
Cause: Browser API used without guard
Fix:   Add `if (typeof window === 'undefined') return`
```

**2. `Cannot find module 'react/jsx-runtime'`**
```
Cause: SSR bundle missing dependencies
Fix:   Verify vite.config.js has `ssr: { noExternal: true }`
       This is already configured in templates 
```

**3. SSR returns empty `<div id="app">`**
```
Cause: SSR server crashed or not running
Debug: Check logs for errors
       Restart: pkill -f ssr.js (supervisor auto-restarts)
```

**4. Page flashes on load**
```
Cause: SSR/client mismatch (normal for theme toggle)
Fix:   Use `suppressHydrationWarning` if intentional
```

---

## Performance

### Benefits
- Faster First Contentful Paint (50-200ms improvement)
- Better SEO (crawlers see content)
- Works without JavaScript
- Improved perceived performance

### Trade-offs
- Server CPU usage (~5-10ms per request)
- More complex debugging
- Must guard browser APIs

### When to Use SSR
- **Public pages** (landing, marketing)
- **Content pages** (blogs, docs)
- **SEO-critical pages**
- **Admin panels** (less important)
- **Highly dynamic apps** (less benefit)

---

## Hot Reload (Production)

**SSR automatically restarts after code changes:**
1. Platform builds new SSR bundle
2. Git push to Fly.io
3. `/vibes/api/reload` kills SSR process
4. Supervisor restarts SSR with new bundle
5. **Total SSR downtime:** ~1.5s
6. **Rails downtime:** 0s

**No manual restart needed!** 

---

## Advanced Topics

### SSR Bundle Location
- **Development:** Uses dev server (dynamic)
- **Production (image):** `/rails/vite/ssr/ssr.js`
- **Production (volume):** `/mnt/data/code/vite/ssr/ssr.js` (hot updates)

### Resilient SSR Loading
The `bin/ssr-server` script prevents stale bundles:
- **Volume boot:** ONLY uses `/mnt/data/code/vite/ssr/ssr.js` (no image fallback)
- **Image boot:** ONLY uses `/rails/vite/ssr/ssr.js` (standard deployment)
- **Missing bundle:** Gracefully exits (app runs without SSR)

This prevents loading stale SSR from image when volume has newer code.

### Supervisor Architecture
- SSR runs in background loop (Fly vibecoding only)
- Auto-restarts on crash (1s delay)
- **Gracefully stops if bundle removed** (exit code 0)
- Independent of Rails process
- App continues running without SSR if bundle missing

---

## Quick Reference

**Enable SSR:**
```ruby
config.ssr_enabled = true  # Already enabled 
```

**Guard browser APIs:**
```jsx
if (typeof window === 'undefined') return
```

**Verify SSR works:**
```bash
curl YOUR_URL | grep '<div id="app">'
# Should see HTML content, not empty div
```

**Restart SSR (if needed):**
```bash
# Local: restart bin/dev
# Fly.io: Auto-restart via supervisor (or pkill -f ssr.js)
```

---

## Resources

- [Inertia.js SSR Guide](https://inertiajs.com/server-side-rendering)
- [React SSR Docs](https://react.dev/reference/react-dom/server)
- [Vite SSR Config](https://vitejs.dev/guide/ssr.html)
- `SSR_HOT_RELOAD_ARCHITECTURE.md` - Detailed architecture docs