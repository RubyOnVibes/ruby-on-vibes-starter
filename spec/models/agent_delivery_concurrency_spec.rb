# frozen_string_literal: true

require "spec_helper"
require "json"
require "open3"
require "rbconfig"
require "tmpdir"

RSpec.describe "Concurrent agent event delivery" do
  it "accepts concurrent duplicate events and dispatches exactly one input and run" do
    Dir.mktmpdir("agent-delivery-concurrency-") do |directory|
      stdout, stderr, status = Open3.capture3(
        { "RAILS_ENV" => "test", "DATABASE_URL" => "sqlite3:#{directory}/events.sqlite3" },
        RbConfig.ruby, "-rbundler/setup", "-e", <<~'SCRIPT'
          require_relative "config/environment"
          require "active_record/fixtures"
          require "json"
          ActiveRecord::Migration.verbose = false
          load Rails.root.join("db/schema.rb")
          unless ActiveRecord::Base.connection.data_source_exists?("agent_deliveries")
            require_relative "db/migrate/20261126000100_create_agent_deliveries"
            CreateAgentDeliveries.new.migrate(:up)
          end
          ActiveRecord::FixtureSet.create_fixtures(Rails.root.join("spec/fixtures"), %w[users workspaces members])
          member = Member.find(ActiveRecord::FixtureSet.identify(:alice_personal_member))
          chat = Chat.create!(member: member, name: "Concurrent inbox")
          agent = Agent.create!(workspace: member.workspace, member: member, chat: chat, name: "Concurrent", identifier: "concurrent")
          ChatStreamJob.queue_adapter = :test
          ActiveRecord::Base.connection_pool.release_connection

          def together
            ready = Queue.new
            start = Queue.new
            workers = 2.times.map do
              Thread.new do
                ActiveRecord::Base.connection_pool.with_connection do
                  ready << true
                  start.pop
                  yield
                end
              end
            end
            2.times { ready.pop }
            2.times { start << true }
            workers.map(&:value)
          end

          receipts = together do
            AgentDelivery.accept!(agent: Agent.find(agent.id), trigger: "webhook",
              payload: '{"invoice_id":"one"}', idempotency_key: "provider-delivery-one").id
          end
          together { AgentDelivery.find(receipts.first).deliver! }
          receipt = AgentDelivery.find(receipts.first)
          puts JSON.generate(ids: receipts, receipts: AgentDelivery.count, messages: chat.messages.count,
            runs: chat.chat_runs.count, status: receipt.status, run_input: receipt.chat_run.input_message_id,
            receipt_input: receipt.input_message_id)
        SCRIPT
      )
      expect(status.success?).to be(true), stderr
      result = JSON.parse(stdout.lines.last)
      expect(result.fetch("ids").uniq.size).to eq(1)
      expect(result).to include("receipts" => 1, "messages" => 1, "runs" => 1, "status" => "dispatched")
      expect(result.fetch("run_input")).to eq(result.fetch("receipt_input"))
    end
  end
end
