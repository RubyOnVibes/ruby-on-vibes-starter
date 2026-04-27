# Caching

## What is Caching?

Caching stores frequently-accessed data in fast memory instead of reading it from the database every time. Think of it like keeping your most-used files on your desk instead of walking to the filing cabinet.

**Benefits:**
- Faster page loads
- Less database load
- Lower server costs

## How This App Uses Caching

### 1. Rails.cache (SolidCache)

Your app uses **SolidCache** for general caching:

```ruby
Rails.cache.fetch("user_stats", expires_in: 1.hour) do
  # Expensive calculation only runs once per hour
  User.calculate_statistics
end
```

**Storage:** Separate SQLite database (`production_cache.sqlite3`) or shared PostgreSQL

**Good for:**
- Computed data (statistics, reports)
- API responses
- Rendered HTML fragments

### 2. Chat Streaming (Throttled Polling)

Chat cancellation uses a different pattern called **throttled polling**:

**Without throttling:**
- Checks database 200+ times during one chat response
- Slows down streaming
- Wastes server resources

**With throttling (what we do):**
- Checks database every 300ms (about 5 times per response)
- Fast cancellation (users don't notice the delay)
- 40× less database load

**How it works:**
1. You click "Stop" on a chat → database updated immediately
2. Streaming job checks database every 300ms
3. Notices the stop within 300-600ms
4. Stream stops (feels instant to you)

**Why not use cache?** Checking a cache database is as slow as checking the main database. Throttling avoids the problem entirely.

## When to Upgrade to Redis

Your app works great without Redis. Consider adding Redis if:

- **You have multiple servers** (load balanced across regions)
- **You have 1000+ concurrent users** 
- **Cache performance becomes a bottleneck**

### Adding Redis (Future)

When you're ready, it's one configuration change:

```ruby
# config/environments/production.rb
config.cache_store = :redis_cache_store, { url: ENV['REDIS_URL'] }
```

Your code doesn't change. Redis just makes caching faster across multiple servers.

## What You Don't Need to Do

✅ Caching is already configured and working  
✅ Chat streaming is already optimized  
✅ No action needed unless you're scaling to thousands of users  

## Performance Tips

### Good Caching

```ruby
# Cache expensive operations
Rails.cache.fetch("dashboard_#{user.id}", expires_in: 5.minutes) do
  user.calculate_dashboard_stats
end
```

### Bad Caching

```ruby
# Don't cache what changes frequently
Rails.cache.fetch("current_user") do
  User.find(session[:user_id])  # This changes every request!
end
```

### Cache Expiration

Always set an expiration time:

- **Fast-changing data:** 1-5 minutes
- **Medium-changing data:** 1 hour
- **Slow-changing data:** 1 day

**Never cache forever** - data becomes stale.

## Clearing Cache

**During development:**
```bash
bin/rails cache:clear
```

**In production:**  
Cache clears automatically when items expire. Manual clearing rarely needed.

## Related Documentation

- [Queue](queue.md) - Background jobs and SolidQueue
