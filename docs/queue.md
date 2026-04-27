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