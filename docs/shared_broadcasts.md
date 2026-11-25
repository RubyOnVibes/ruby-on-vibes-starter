# Shared broadcasts

Chat execution and deferred Turbo broadcasts run through Solid Queue. Run both
the web server and `bin/jobs`; `bin/dev` starts both for local development.
Action Cable uses Solid Cable in development and production, so a worker can
publish updates to browsers connected to another process. `async-cable` supplies
the Falcon WebSocket transport; it does not replace the shared subscription
adapter. Tests retain Rails' test adapter.

Solid Cable's table is installed by a normal primary-database migration. This
keeps the starter's existing SQLite, PostgreSQL, and optional mounted database
configurations usable without Redis or an additional database. Both web and
worker must connect to the same primary database; separate machines cannot share
independent SQLite files. For a larger deployment, move this table to a dedicated
cable database using [Solid Cable's configuration](https://github.com/rails/solid_cable#installation).
That isolates streaming traffic and trimming from business writes.

Events poll every 100 ms and are retained for five minutes to bound storage growth
during streaming. These are transient delivery notifications, not an event log:
the browser reloads persisted messages and run status when it reconnects. An
interrupted stream does not imply that its background execution was cancelled.
RubyLLM persists conversation state and the application persists run state.

Turbo broadcast jobs use the application's queue adapter too. The previous
in-process override is removed; restarting the web process no longer discards
enqueued broadcasts. The worker is therefore required for deferred Turbo updates
as well as agent execution.

Run `bundle exec ruby script/check_shared_broadcasts.rb` to verify cross-process
delivery with the configured development adapter. The check boots two Rails
processes and gives them an isolated temporary SQLite database; it does not
modify application records or call a model provider. It also verifies the cable
migration can be rolled back. This checks transport, while the agent execution
tests and demo exercise durable dispatch and browser behavior.
