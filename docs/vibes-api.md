# Vibes API — Hosted Platform Sync Surface

The `Vibes::Api` controllers in `app/controllers/vibes/api/` exist to let the hosted Ruby on Vibes platform sync code changes, hot-reload config, and seed admin users into running app instances. Self-hosters generally do not need to enable them.

## Default: off

The routes are not mounted unless you explicitly opt in:

```bash
VIBES_API_ENABLED=true
```

Without this env var, hitting any `/vibes/api/*` path returns 404.

## Auth: fail-closed

Once routes are mounted, every endpoint (except `/vibes/api/health`) requires a static token sent as the `X-Vibes-Token` header. The token is compared against `ENV['VIBES_API_TOKEN']`.

If `VIBES_API_TOKEN` is blank, **every request returns 401**. There is no silent pass.

```bash
VIBES_API_TOKEN=<long-random-string>
```

Use a secret manager (Fly secrets, Render env groups, Kubernetes secrets, etc.) — never commit it.

## Endpoints

| Method | Path                        | Purpose                                                                    |
|--------|-----------------------------|----------------------------------------------------------------------------|
| GET    | `/vibes/api/health`         | Health probe. Skips auth. Returns minimal payload unless `USE_MOUNTED_VIBES=true`. |
| POST   | `/vibes/api/reload`         | Reload Rails routes/schema/Vite/SSR after a code change is synced in.      |
| POST   | `/vibes/api/git_pull`       | `git reset --hard origin/main` on `/mnt/data/code` (platform layout only). |
| POST   | `/vibes/api/users/admins`   | Bulk-create initial admin users (no-op once two admins exist).             |

## Risks if exposed

`git_pull` runs a destructive `git reset --hard`. `reload` reloads code in-place. `users/admins` creates admin users from a request body. **Never expose these endpoints to the public internet without a non-trivial token.** If you do not need them, leave `VIBES_API_ENABLED` unset.

## Future

The endpoints will likely be extracted into a mountable Rails engine in v0.2 so the public template doesn't carry the surface at all.
