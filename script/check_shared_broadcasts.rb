# frozen_string_literal: true

# Run with: bundle exec ruby script/check_shared_broadcasts.rb
# Uses two real Rails processes and its own temporary SQLite database. No model
# provider is called and no application database is migrated or cleared.
ENV["RAILS_ENV"] ||= "development"
require_relative "../config/environment"
require "tmpdir"
require "timeout"
require "open3"

def use_probe_database(path)
  configuration = { adapter: "sqlite3", database: path, pool: 5, timeout: 5_000 }
  ActiveRecord::Base.establish_connection(configuration)
  SolidCable::Record.establish_connection(configuration)
end

class SharedBroadcastProbeJob < ApplicationJob
  def perform(channel)
    ActionCable.server.broadcast(channel, { event: "worker_completed", pid: Process.pid })
  end
end

unless ActionCable.server.config.cable.fetch("adapter") == "solid_cable"
  abort "Run this check in an environment configured to use Solid Cable (development by default)."
end

if ARGV.first == "--publish"
  use_probe_database(ARGV.fetch(1))
  SharedBroadcastProbeJob.perform_now(ARGV.fetch(2))
  # Solid Cable batches writes; graceful shutdown flushes the last batch.
  ActionCable.server.pubsub.shutdown
else
  Dir.mktmpdir("starter-cable-check-") do |directory|
    use_probe_database(File.join(directory, "probe.sqlite3"))
    require Rails.root.join("db/migrate/20261125000300_create_solid_cable_messages")
    migration = CreateSolidCableMessages.new
    migration.migrate(:up)

    received = Queue.new
    subscribed = Queue.new
    channel = "shared-broadcast-check-#{SecureRandom.hex(8)}"
    callback = lambda do |payload|
      # Falcon's actioncable-next wraps raw data in a Message object.
      received << JSON.parse(payload.respond_to?(:data) ? payload.data : payload)
    end
    ActionCable.server.pubsub.subscribe(channel, callback, -> { subscribed << true })
    Timeout.timeout(10) { subscribed.pop }

    output, error, status = Open3.capture3(
      RbConfig.ruby, __FILE__, "--publish", File.join(directory, "probe.sqlite3"), channel
    )
    raise "Publisher failed: #{output}\n#{error}" unless status.success?

    event = Timeout.timeout(10) { received.pop }
    unless event["event"] == "worker_completed" && event["pid"] != Process.pid
      raise "Expected a broadcast from a separate process"
    end

    ActionCable.server.pubsub.unsubscribe(channel, callback)
    ActionCable.server.pubsub.shutdown
    migration.migrate(:down)
    if ActiveRecord::Base.connection_pool.with_connection { |connection| connection.table_exists?(:solid_cable_messages) }
      raise "Migration rollback failed"
    end

    puts "Shared broadcast received from a separate job process; migration rollback passed."
  ensure
    ActiveRecord::Base.connection_pool.disconnect!
    SolidCable::Record.connection_pool.disconnect!
  end
end
