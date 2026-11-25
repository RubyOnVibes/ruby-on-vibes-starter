# frozen_string_literal: true

# bundle exec ruby script/check_job_delivery.rb
#
# Proves actual Solid Queue delivery to ChatStreamJob in a separate worker.
# Primary and queue state live in disposable SQLite files. Provider replies are
# scripted, HTTP is blocked, and no existing server or worker is used.
require "tmpdir"
require "timeout"
require "rbconfig"
require "fileutils"

child_mode = ARGV.first == "--worker"
directory = child_mode ? ARGV.fetch(1) : Dir.mktmpdir("starter-queue-check-")
database = File.join(directory, "primary.sqlite3")
queue_database = File.join(directory, "queue.sqlite3")
worker_log = File.join(directory, "worker.log")
stop_file = File.join(directory, "stop")
delivery_log = File.join(directory, "deliveries.jsonl")
worker_pid = nil

begin
  ENV["RAILS_ENV"] = "test"
  ENV["DATABASE_URL"] = "sqlite3:#{database}"
  ENV["PRIMARY_DATABASE_URL"] = ENV["DATABASE_URL"]
  ENV["QUEUE_DATABASE_URL"] = "sqlite3:#{queue_database}"
  ENV["CACHE_DATABASE_URL"] = "sqlite3:#{File.join(directory, 'cache.sqlite3')}"
  ENV["OPENAI_API_KEY"] = "queue-check-no-network"
  ENV["ANTHROPIC_API_KEY"] = "queue-check-no-network"
  ENV["LLM_MODEL"] = "claude-sonnet-4-6"
  ENV["LLM_FALLBACK_MODELS"] = ""
  require_relative "../config/boot"
  require "net/http"
  Net::HTTP.prepend(Module.new do
    def request(*)
      raise "HTTP is disabled by the queue check"
    end
  end)
  require_relative "../config/environment"
  require "ruby_llm/test_helper"
  require "active_record/fixtures"

  # Also reject provider transport before an adapter can attempt a connection.
  Faraday::Connection.prepend(Module.new do
    def run_request(*)
      raise "Provider HTTP is disabled by the queue check"
    end
  end)
  Rails.logger = Logger.new(File.join(directory, "rails.log"))
  SolidQueue.logger = Rails.logger
  primary_config = { adapter: "sqlite3", database: database, pool: 8, timeout: 10_000 }
  queue_config = primary_config.merge(database: queue_database)
  ActiveRecord::Base.establish_connection(primary_config)
  SolidQueue::Record.establish_connection(queue_config)

  # test.rb normally captures jobs. This probe deliberately replaces that
  # adapter for application jobs with the real persistent queue in BOTH processes.
  ApplicationJob.queue_adapter = :solid_queue
  raise "Real queue adapter is required" unless ChatStreamJob.queue_adapter.is_a?(ActiveJob::QueueAdapters::SolidQueueAdapter)
  SolidQueue.preserve_finished_jobs = true
  RubyLLM.configure { |config| config.max_run_time = 10 }

  module JobDeliveryProbe
    extend RubyLLM::TestHelper

    def self.assert(condition, message)
      raise message unless condition
    end

    def self.wait_for(message, seconds: 30)
      Timeout.timeout(seconds) { sleep 0.05 until yield }
    rescue Timeout::Error
      raise "Timed out: #{message}"
    end

    def self.snapshot(run)
      run.reload
      {
        status: run.status,
        input_id: run.input_message_id,
        user_messages: run.chat.messages.where(role: :user).pluck(:id, :content),
        assistant_messages: run.chat.messages.where(role: :assistant).pluck(:id, :content),
        usage_ids: run.owned_llm_usages.order(:id).pluck(:id),
        usage_summary: run.usage_summary
      }
    end
  end

  if child_mode
    JobDeliveryProbe.stub_replies "Completed through the real queue.", cost: 0.01
    # Observe the actual deserialized ActiveJob without replacing its behavior.
    ChatStreamJob.around_perform do |job, perform|
      File.open(delivery_log, "a") do |file|
        file.puts({ pid: Process.pid, run_id: job.arguments.first, job_id: job.job_id }.to_json)
      end
      perform.call
    end
    stop_requested = false
    Signal.trap("TERM") { stop_requested = true }
    Signal.trap("INT") { stop_requested = true }
    worker = SolidQueue::Worker.new(queues: [ "agents" ], threads: 1, polling_interval: 0.05)
    begin
      worker.start
      sleep 0.05 until stop_requested || File.exist?(stop_file)
    ensure
      worker.stop
    end
  else
    ActiveRecord::Migration.verbose = false
    # Schema loading acts on Base; restore its primary connection before models
    # or fixtures are used. SolidQueue::Record always has its separate queue pool.
    ActiveRecord::Base.establish_connection(queue_config)
    load Rails.root.join("db/queue_schema.rb")
    ActiveRecord::Base.establish_connection(primary_config)
    load Rails.root.join("db/schema.rb")
    ActiveRecord::FixtureSet.create_fixtures(Rails.root.join("spec/fixtures"), %w[users workspaces members])
    user = User.find_by!(email: "alice@example.com")
    member = Member.find_by!(user: user, workspace: Workspace.find_by!(name: "Personal Workspace", owner: user))
    chat = Chat.create!(member: member, name: "Real queue delivery")
    input = chat.messages.create!(role: :user, content: "Complete one queued turn.", member: member, user: user)
    run = chat.chat_runs.create!(initiated_by_member: member, input_message: input, status: :pending)

    JobDeliveryProbe.assert(run.dispatch!, "Run was not enqueued")
    first_job = SolidQueue::Job.where(class_name: "ChatStreamJob").sole
    JobDeliveryProbe.assert(first_job.ready_execution.present?, "Job did not reach the real ready queue")
    JobDeliveryProbe.assert(run.reload.status_pending?, "Run executed before a worker was started")
    worker_pid = Process.spawn(RbConfig.ruby, __FILE__, "--worker", directory, out: worker_log, err: worker_log)
    JobDeliveryProbe.wait_for("queued run to complete") do
      first_job.reload.finished_at.present? && run.reload.status_completed?
    end

    before_duplicate = JobDeliveryProbe.snapshot(run)
    JobDeliveryProbe.assert(before_duplicate[:user_messages] == [ [ input.id, input.content ] ], "Delivery appended another user turn")
    JobDeliveryProbe.assert(before_duplicate[:assistant_messages].map(&:last) == [ "Completed through the real queue." ], "Unexpected assistant response")
    JobDeliveryProbe.assert(before_duplicate[:usage_ids].size == 1, "Native usage was not recorded exactly once")
    JobDeliveryProbe.assert(run.llm_attempts == 1 && run.total_cost == BigDecimal("0.01"), "Run did not capture native usage")

    duplicate = ChatStreamJob.perform_later(run.id)
    duplicate_job = SolidQueue::Job.find_by!(active_job_id: duplicate.job_id)
    JobDeliveryProbe.wait_for("duplicate queued job to finish") { duplicate_job.reload.finished_at.present? }
    JobDeliveryProbe.assert(JobDeliveryProbe.snapshot(run) == before_duplicate, "Duplicate delivery changed persisted conversation or usage")
    JobDeliveryProbe.assert(chat.chat_runs.count == 1, "Delivery created an extra run")
    JobDeliveryProbe.assert(SolidQueue::FailedExecution.none?, "Queue contains failed executions")
    deliveries = File.readlines(delivery_log).map { |line| JSON.parse(line) }
    JobDeliveryProbe.assert(deliveries.size == 2 && deliveries.all? { |event| event["pid"] == worker_pid && event["run_id"] == run.id },
      "Both deliveries must execute in the separate worker")
    JobDeliveryProbe.assert(deliveries.map { |event| event["job_id"] }.sort == [ first_job.active_job_id, duplicate.job_id ].sort,
      "The worker did not execute the two enqueued ActiveJobs")

    puts "PASS: real Solid Queue worker completed one persisted run, one user turn and one native usage record."
    puts "PASS: a duplicate queued job finished in the separate worker without changing messages or usage."
    puts "Temporary primary/queue databases only; scripted provider replies; HTTP blocked."
  end
rescue Exception
  if !child_mode && File.exist?(worker_log)
    warn File.readlines(worker_log).last(40).join
    warn File.readlines(File.join(directory, "rails.log")).last(40).join if File.exist?(File.join(directory, "rails.log"))
  end
  raise
ensure
  unless child_mode
    if worker_pid
      File.write(stop_file, "stop")
      begin
        Timeout.timeout(10) { Process.wait(worker_pid) }
      rescue Timeout::Error
        Process.kill("TERM", worker_pid) rescue Errno::ESRCH
        begin
          Timeout.timeout(5) { Process.wait(worker_pid) }
        rescue Timeout::Error
          Process.kill("KILL", worker_pid) rescue Errno::ESRCH
          Process.wait(worker_pid) rescue Errno::ECHILD
        end
      rescue Errno::ECHILD
        # A previously reaped worker needs no further cleanup.
      end
    end
  end
  ActiveRecord::Base.connection_handler.clear_all_connections! if defined?(ActiveRecord::Base)
  FileUtils.remove_entry(directory) if !child_mode && File.directory?(directory)
end
