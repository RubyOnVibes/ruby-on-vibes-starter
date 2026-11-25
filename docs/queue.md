# Using Solid Queue

Two config files matter:

- `config/queue.yml` – worker processes:
  - Controls worker processes/threads (`processes`, `threads`, `queues`, `polling_interval`).
  - This template is tuned for small single‑machine Fly dev servers, but all values can be overridden via `SOLID_QUEUE_*` env vars.

- `config/recurring.yml` – cron‑style recurring tasks:
  - Each entry defines either a job class (`class: SomeJob`) or a command (`command: "SomeModel.method"`) plus a human‑readable `schedule` string.
  - Example:
    - `class: RefreshModelsJob`, `queue: default`, `schedule: at 3am every day`
  - With `RAILS_ENV=production` and a running worker (`bin/jobs`), recurring tasks are executed automatically.

## RubyLLM claim renewal capacity

RubyLLM renews each active conversation's database claim from a background
thread. Reserve one additional primary-database connection per concurrently
running chat, beyond the connections used by the jobs themselves. The default
`SOLID_QUEUE_THREADS=2` and primary pool of 5 provide room for two job threads,
two claim-renewal threads and one spare connection in each worker process.

If you raise worker concurrency, review `RAILS_MAX_THREADS` (the database pool
setting in `config/database.yml`) too. Count other database consumers in that
process; increasing `SOLID_QUEUE_PROCESSES` adds separate pools and increases
total database connections. In PostgreSQL configurations that put queue and
application tables in the same database, include both connection pools in the
server's connection budget.

The default RubyLLM `max_run_time` is ten minutes without progress. Keep slow
model requests and synchronous tools below that bound, or return a native task
and let an ordinary job do the work. A process that dies stops renewing, so its
claim expires and the starter's recurring run sweep can redeliver the intent.
See [RubyLLM background jobs](https://rubyllm.com/durable-agents/#one-process-at-a-time)
for claim renewal and the requirements of tenant-scoped database connections.
