# Upgrading from SQLite to PostgreSQL (Supabase)

Your app starts with SQLite (fast, simple, free). When you need more scale, upgrade to PostgreSQL.

**⚠️ CRITICAL ORDER:** Set up PostgreSQL tables BEFORE changing DATABASE_URL!  
If you change DATABASE_URL first, your app will crash (tables don't exist yet).

## Setup (5 minutes)

### 1. Create Supabase Database

1. Create account and a project at [supabase.com](https://supabase.com) (free tier, no credit card)
2. **IMPORTANT:** Select region closest to your Fly app:
   - Check your app's region in the `fly.toml` file
   - Match it to an AWS region name with AI: IAD → us-east-1, ORD → us-east-1, SJC → us-west-1, etc
   - **Latency matters!** Wrong region = 30-50ms per query
3. Set strong database password (save it!)

### 2. Get Connection URL - COPY it to your clipboard

**Supabase Dashboard → Project → Settings → Database → Connect → URI**

Copy the URI and **replace `[YOUR-PASSWORD]` with your actual database password:**

```
postgresql://postgres:[YOUR-PASSWORD]@db.xxxxxx.supabase.co:5432/postgres
```

### 3. Load All Schemas on PostgreSQL

**⚠️ CRITICAL: Do this step BEFORE you change DATABASE_URL in Settings!**

Your app is still running on SQLite. Use MCP console to set up Supabase tables, THEN change DATABASE_URL.

**Open Backend Console (MCP)** - click the MCP button in the toolbar, then go to the **Shell** tab.

Paste this Ruby code to set up your PostgreSQL database (replace with YOUR connection URL):

```ruby
# Use YOUR actual connection URL with password
url = "postgresql://postgres:YOUR_PASSWORD@db.xxxxxx.supabase.co:5432/postgres"

# Setup environment
ENV['DATABASE_URL'] = url
ENV['DISABLE_DATABASE_ENVIRONMENT_CHECK'] = '1'

# Load PRIMARY schema (users, posts, etc)
ActiveRecord::Base.establish_connection(adapter: 'postgresql', url: url)
load Rails.root.join('db/schema.rb')
puts "✅ Primary tables: #{ActiveRecord::Base.connection.tables.count}"

# Load CACHE schema (Solid Cache)
ActiveRecord::Base.establish_connection(adapter: 'postgresql', url: url)
load Rails.root.join('db/cache_schema.rb')
cache_tables = ActiveRecord::Base.connection.tables.grep(/solid_cache/).count
puts "✅ Cache tables: #{cache_tables}"

# Load QUEUE schema (Solid Queue)
ActiveRecord::Base.establish_connection(adapter: 'postgresql', url: url)
load Rails.root.join('db/queue_schema.rb')
queue_tables = ActiveRecord::Base.connection.tables.grep(/solid_queue/).count
puts "✅ Queue tables: #{queue_tables}"

# Final verification
ActiveRecord::Base.establish_connection(adapter: 'postgresql', url: url)
total = ActiveRecord::Base.connection.tables.count
puts "\n🎉 Total tables: #{total} (primary + cache + queue)"
```

Press **Cmd+Enter** to execute. Should output all three schema loads successfully.

**Verify schemas loaded:**
```ruby
ActiveRecord::Base.establish_connection(adapter: 'postgresql', url: url)
puts ActiveRecord::Base.connection.tables.count
# Should output: 20+ (primary + cache + queue tables)
```

### 4. Update Database URL (AFTER Schemas are Loaded)

**NOW you can safely change DATABASE_URL:**

Go to **Settings → Secrets** and update:

⚠️ CRITICAL: SET BOTH THE FOLLOWING VARIABLES TO 'User-provided' IN CASE THIS APP IS EVER PUBLISHED  

- `DATABASE_URL` → Your Supabase connection URL
- `BLAZER_DATABASE_URL` → Same Supabase connection URL

Click **Save** - your app will automatically restart.

### 5. Verify It Works

After restart (~15 seconds), open **Backend Console → Shell** again and run:

```ruby
ActiveRecord::Base.connection_db_config.adapter

```

Should output: `PostgreSQL` in the `STDOUT` (AKA standard output)

Done! Your app is now running on PostgreSQL.

## What Gets Upgraded

**Single PostgreSQL database contains all three:**
- Primary tables (users, posts, etc)
- Cache tables (solid_cache_entries)
- Queue tables (solid_queue_jobs, etc)

Rails 8 can use or more databases for all three systems.

## Region Matching for Performance

**Critical:** Your Fly app and Supabase database should be in the same region!

### Your Fly Region

**Default Setup:**
- Your app deploys to **IAD (Virginia)** by default
- Use Supabase **us-east-1** for best performance
- This gives low database latency (vs cross-region)

### If You Need a Different Region

Contact support to change your app's Fly region before upgrading to PostgreSQL.

## Troubleshooting

### "Connection refused" or IPv6 errors

**Check Network Bans:**
1. Supabase Dashboard → Project → Settings → Database
2. Scroll to **"Network Restrictions"** or **"Network Bans"**
3. Make sure your Fly app IP is not banned

### "Password authentication failed"

- Double-check you replaced `[YOUR-PASSWORD]` with your actual database password
- Try resetting the database password in Supabase dashboard

## Why PostgreSQL?

SQLite is great for getting started, but PostgreSQL enables:
- Concurrent writes (SQLite locks on writes)
- Better connection pooling
- Advanced indexing
- Full-text search
- JSON/JSONB with indexing
- Extensions (pgvector for AI, postgis for maps)
- Industry standard

## Optional: Upgrade JSON to JSONB

SQLite stores JSON as text. PostgreSQL has two JSON types—`json` and `jsonb`. Your existing `json` columns work fine, but `jsonb` is faster for queries and supports indexing.

**Create a migration:**
```bash
rails g migration ChangeJsonColumnsToJsonb
```

**Example migration:**
```ruby
class ChangeJsonColumnsToJsonb < ActiveRecord::Migration[8.0]
  def up
    change_column :my_table, :settings, :jsonb
  end

  def down
    change_column :my_table, :settings, :json
  end
end
```

Only worth doing if you query JSON contents frequently. Skip if you just store/retrieve whole objects.