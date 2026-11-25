# frozen_string_literal: true

# bundle exec ruby script/check_durable_execution.rb
#
# Exercises the real job and native conversation loop across separate Ruby
# processes. Only its temporary SQLite database is loaded/changed. Provider
# replies are scripted and HTTP is blocked. Jobs are delivered explicitly by
# this harness: this proves persisted execution/recovery, not queue supervision.
require "tmpdir"
require "open3"
require "timeout"
require "rbconfig"

child_mode = ARGV.first&.start_with?("--")
directory = child_mode ? File.dirname(ARGV.fetch(1)) : Dir.mktmpdir("starter-durability-check-")
database = child_mode ? ARGV.fetch(1) : File.join(directory, "probe.sqlite3")
ENV["RAILS_ENV"] = "test"
ENV["DATABASE_URL"] = "sqlite3:#{database}"
ENV["OPENAI_API_KEY"] = "durability-check-no-network"
ENV["ANTHROPIC_API_KEY"] = "durability-check-no-network"
ENV["LLM_MODEL"] = "claude-sonnet-4-6"
ENV["LLM_FALLBACK_MODELS"] = ""
require_relative "../config/environment"
require "ruby_llm/test_helper"
require "active_record/fixtures"
# RubyLLM uses Faraday for provider transport. Any accidental real provider
# request must fail instead of escaping the scripted conversation loop.
Faraday::Connection.prepend(Module.new do
  def run_request(*)
    raise "Provider HTTP is disabled by the durability check"
  end
end)
Rails.logger = Logger.new(File.join(directory, "rails.log"))
ActiveRecord::Base.establish_connection(adapter: "sqlite3", database: database, pool: 8, timeout: 10_000)
ApplicationJob.queue_adapter = :test
RubyLLM.configure { |config| config.max_run_time = 10 }

class DurabilityProbeEvent < ActiveRecord::Base
  self.table_name = "durability_probe_events"
end

class DurabilityProbeEffect < ActiveRecord::Base
  self.table_name = "durability_probe_effects"
end

class DurabilityProbeTool < RubyLLM::Tool
  description "Exercise a locally isolated durable operation"
  parameters do
    string :operation, enum: %w[defer preserved crash concurrent]
  end

  def initialize(run:)
    @run = run
  end

  def execute(operation:)
    record(operation)
    case operation
    when "defer"
      RubyLLM::Task.new(status: :working, poll_interval: 1, data: { "run_id" => @run.id })
    when "preserved"
      "Completed before the worker stopped"
    when "crash"
      # Exit without rescue/ensure, just like a killed worker. The persisted
      # native claim must expire before another process can recover it.
      Process.exit!(77)
    when "concurrent"
      # The native claim prevents duplicate execution; the separate unique
      # operation key illustrates the business-level protection effects need.
      DurabilityProbeEffect.create_or_find_by!(operation_key: "run:#{@run.id}")
      release = File.join(File.dirname(ActiveRecord::Base.connection_db_config.database), "release")
      Timeout.timeout(8) { sleep 0.05 until File.exist?(release) }
      "One business effect"
    end
  end

  def resume(task, **)
    raise "Task resumed with the wrong persisted state" unless task.data.fetch("run_id") == @run.id

    record("resume")
    "Deferred operation completed in a fresh process"
  end

  private

  def record(event)
    DurabilityProbeEvent.create!(run_id: @run.id, event: event, process_id: Process.pid)
  end
end

class DurabilityProbeAgent < ApplicationAgent
  instructions "Complete the supplied local validation operation."
  tools { [DurabilityProbeTool.new(run: run_context.run)] }
  tool_options rounds: 5, calls: 5
end

ChatPurpose.singleton_class.prepend(Module.new do
  def registry
    super.merge("durability_probe" => DurabilityProbeAgent)
  end
end)

module DurabilityProbe
  extend RubyLLM::TestHelper

  def self.assert(condition, message)
    raise message unless condition
  end

  def self.wait_for(message, seconds: 15)
    Timeout.timeout(seconds) { sleep 0.05 until yield }
  rescue Timeout::Error
    raise "Timed out: #{message}"
  end

  def self.command(mode, database, run)
    [RbConfig.ruby, __FILE__, "--#{mode}", database, run.id.to_s]
  end

  def self.deliver(mode, database, run, expected_exit: 0)
    output, error, status = Open3.capture3(*command(mode, database, run))
    assert(status.exitstatus == expected_exit, "#{mode} exited #{status.exitstatus}: #{output}\n#{error}")
  end

  def self.new_run(member, name)
    chat = Chat.create!(member: member, name: name, purpose: "durability_probe")
    message = chat.messages.create!(role: :user, content: name, member: member, user: member.user)
    chat.chat_runs.create!(initiated_by_member: member, input_message: message, status: :pending)
  end
end

if child_mode
  run = ChatRun.find(ARGV.fetch(2))
  case ARGV.first
  when "--defer"
    DurabilityProbe.stub_replies DurabilityProbe.tool_call(:durability_probe, operation: "defer"), "Must wait"
  when "--resume", "--recover"
    DurabilityProbe.stub_replies "Recovered and completed."
  when "--crash"
    DurabilityProbe.stub_replies(
      DurabilityProbe.tool_call(:durability_probe, operation: "preserved"),
      DurabilityProbe.tool_call(:durability_probe, operation: "crash"),
      "Must not reach this before recovery"
    )
  when "--concurrent"
    DurabilityProbe.stub_replies DurabilityProbe.tool_call(:durability_probe, operation: "concurrent"), "Completed once."
  else
    raise "Unknown probe mode"
  end
  ChatStreamJob.perform_now(run.id)
else
  begin
    ActiveRecord::Migration.verbose = false
    load Rails.root.join("db/schema.rb")
    ActiveRecord::Schema.define do
      create_table(:durability_probe_events) do |table|
        table.integer :run_id, null: false
        table.string :event, null: false
        table.integer :process_id, null: false
      end
      create_table(:durability_probe_effects) do |table|
        table.string :operation_key, null: false, index: { unique: true }
      end
    end
    ActiveRecord::FixtureSet.create_fixtures(Rails.root.join("spec/fixtures"), %w[users workspaces members])
    member = Member.find_by!(user: User.find_by!(email: "alice@example.com"), workspace: Workspace.find_by!(name: "Personal Workspace", owner: User.find_by!(email: "alice@example.com")))

    run = DurabilityProbe.new_run(member, "Task survives process exit")
    DurabilityProbe.deliver("defer", database, run)
    DurabilityProbe.assert(run.reload.status_awaiting_tasks?, "Native task did not persist its wait")
    DurabilityProbe.assert(run.chat.reload.pending_tasks.size == 1, "Native task state was not persisted")
    DurabilityProbe.deliver("resume", database, run)
    events = DurabilityProbeEvent.where(run_id: run.id)
    DurabilityProbe.assert(run.reload.status_completed?, "Task did not complete after reload")
    DurabilityProbe.assert(events.where(event: "defer").count == 1 && events.where(event: "resume").count == 1,
      "Task restarted execute instead of calling resume")
    DurabilityProbe.assert(events.distinct.count(:process_id) == 2, "Task was not resumed in a separate process")
    puts "PASS: native task persisted in process A and resumed in process B; execute ran once."

    run = DurabilityProbe.new_run(member, "Recover an interrupted tool")
    DurabilityProbe.deliver("crash", database, run, expected_exit: 77)
    preserved = run.chat.messages.where(role: :tool).sole
    DurabilityProbe.assert(preserved.content == "Completed before the worker stopped", "Completed tool result was not saved")
    DurabilityProbe.wait_for("native interrupted claim to expire") { Chat.interrupted.exists?(id: run.chat_id) }
    DurabilityProbe.assert(run.reload.recover!, "Durable run did not dispatch recovery")
    DurabilityProbe.deliver("recover", database, run)
    DurabilityProbe.assert(run.reload.status_completed?, "Interrupted run did not complete")
    DurabilityProbe.assert(preserved.reload.content == "Completed before the worker stopped", "Recovery changed the completed result")
    DurabilityProbe.assert(DurabilityProbeEvent.where(run_id: run.id, event: "crash").count == 1,
      "Recovery replayed the interrupted side-effecting tool")
    interrupted_result = run.chat.messages.where(role: :tool).where.not(id: preserved.id).sole
    DurabilityProbe.assert(interrupted_result.to_llm.tool_error_message.present?, "Interrupted tool did not get an explicit failure result")
    puts "PASS: abrupt worker exit recovered after actual lease expiry; prior result preserved and interrupted tool not replayed."

    run = DurabilityProbe.new_run(member, "Concurrent deliveries")
    worker_log = File.join(directory, "concurrent.log")
    worker = Process.spawn(*DurabilityProbe.command("concurrent", database, run), out: worker_log, err: worker_log)
    DurabilityProbe.wait_for("first worker to enter the effect") do
      DurabilityProbeEvent.exists?(run_id: run.id, event: "concurrent")
    end
    DurabilityProbe.deliver("concurrent", database, run)
    File.write(File.join(directory, "release"), "continue")
    _, status = Process.wait2(worker)
    worker = nil
    DurabilityProbe.assert(status.success?, "First concurrent worker failed: #{File.read(worker_log)}")
    DurabilityProbe.deliver("concurrent", database, run)
    DurabilityProbe.assert(run.reload.status_completed?, "Concurrent run did not complete")
    DurabilityProbe.assert(DurabilityProbeEvent.where(run_id: run.id, event: "concurrent").count == 1,
      "Overlapping deliveries executed the tool more than once")
    DurabilityProbe.assert(DurabilityProbeEffect.where(operation_key: "run:#{run.id}").count == 1,
      "Business effect was not unique")
    puts "PASS: overlapping same-run deliveries and a later redelivery produced one tool execution and one keyed effect."
    puts "All checks used temporary state and scripted provider responses; queue supervision and remote API idempotency are separate checks."
  ensure
    if worker
      Process.kill("TERM", worker) rescue Errno::ESRCH
      Process.wait(worker) rescue Errno::ECHILD
    end
    ActiveRecord::Base.connection_pool.disconnect!
    FileUtils.remove_entry(directory)
  end
end
