# Deploy using render.com (PostgreSQL database)

**Best for:** Apps needing to scale, high traffic, multiple workers

### Setup

**1. Use PostgreSQL render config:**

1. **Critical: Rename `render.postgres.yaml` to `render.yaml`**

2. **Edit `render.yaml` - change app and service names (optional):**

Find and replace `myapp-web` and `myapp-db` and `myapp-worker` with your app name.

### 2. Setup Render

- New → Blueprint (connect your GitHub repo for the RubyOnVibes app)
- Click Apply
- Database + services deploy automatically

**Note:** PostgreSQL uses preDeployCommand for migrations. Web + worker scale independently.

---

## Supabase Alternative (instead of render.com manage postgresql)

**1. Set up a supabase account, get a new connection url and set your vibes app up to use Supabase (see docs/supabase.md).**

**2. Remove db info from `render.yaml` so render doesn't autocreate a pg db for your app**

**3. Follow the postgres deploy plan (web and worker scale horizontally, ps can be scaled on Supabase)**

**4. CRITICAL: Set your `DATABASE_URL` ENV VAR on render to be your new prod Postgres URL (from Supabase or other)**

Step 4 wires up your Supabase database to your Rails app by setting the env var. We recommend environment groups per env that your webs and worker nodes share (production group, staging group if necessary, etc).

You will need to run `bundle exec rake db:create db:migrate` after wiring up your Render app to connect to Supabase.