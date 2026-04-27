# Deploy using render.com (SQLite databases)

**Best for:** MVPs, hobby projects, single-instance apps (can't scale horizontally)

### 1. Configure

1. **Critical: Rename `render.sqlite.yaml` to `render.yaml`**

2. **Edit `render.yaml` - change app name (optional):**

```yaml
services:
  - name: myapp  # Change this (optional)
```

### 2. Setup Render

1. Create account at [render.com](https://render.com)
2. Connect your GitHub repo
3. **New → Blueprint** (connect your GitHub repo for the RubyOnVibes app)
4. Render detects `render.yaml` (ensure you sync your RubyOnVibe changes to GitHub)
5. In the render.com shell —  after your Dockerfile builds and the app boots:

```bash
 bundle exec rake db:migrate`
 chown -R rails:rails /mnt/data/sqlite/
```