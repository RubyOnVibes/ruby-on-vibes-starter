# frozen_string_literal: true

require "spec_helper"
require "json"
require "open3"
require "rbconfig"

RSpec.describe "RubyLLM 2.0 cleanup" do
  # A separate process keeps migration DDL and connection changes away from
  # the application's fixture database, even when the full suite loads Rails.
  def cleanup_result(**options)
    migration = File.expand_path("../../db/migrate/20261113005421_cleanup_ruby_llm_v2_upgrade.rb", __dir__)
    stdout, stderr, status = Open3.capture3(
      RbConfig.ruby, "-rbundler/setup", "-e", <<~'RUBY', migration, JSON.generate(options)
        require "active_record"
        require "json"

        ActiveRecord::Base.establish_connection(adapter: "sqlite3", database: ":memory:")
        ActiveRecord::Migration.verbose = false
        options = JSON.parse(ARGV.fetch(1))
        connection = ActiveRecord::Base.connection

        ActiveRecord::Schema.define do
          create_table :messages do |t|
            t.string :role
            t.text :content
            t.json :raw_content
            t.integer :model_id
            t.integer :tool_call_id
            t.json :content_raw
            t.integer :input_tokens
            t.integer :output_tokens
            t.integer :cached_tokens
            t.integer :cache_creation_tokens
            t.integer :cache_read_tokens
            t.integer :cache_write_tokens
            t.integer :thinking_tokens
            t.decimal :total_cost
            t.json :cost_details
            t.index :role
            t.index :model_id
            t.index :tool_call_id
          end
          create_table :ruby_llm_tool_calls do |t|
            t.integer :message_id
            t.integer :result_id
          end
          create_table :ruby_llm_usages do |t|
            t.integer :message_id
            t.integer :input_tokens
            t.decimal :total_cost
          end
          unless options["progress_table"] == false
            create_table :ruby_llm_v2_backfills, id: false do |t|
              t.string :task
              t.boolean :completed
            end
          end
          create_table :ruby_llm_v2_upgrades if options["copy_mode"]
        end

        unless options["empty_messages"]
          connection.execute("INSERT INTO messages (id, role, content, raw_content) VALUES (1, 'assistant', 'Calling tool', '{\"native\":true}')")
          connection.execute("INSERT INTO messages (id, role, content) VALUES (2, 'tool', 'Original tool result')")
          connection.execute("INSERT INTO ruby_llm_tool_calls (id, message_id, result_id) VALUES (1, 1, 2)")
          connection.execute("INSERT INTO ruby_llm_usages (id, message_id, input_tokens, total_cost) VALUES (1, 1, 42, 0.125)")
        end
        options.fetch("legacy_values", {}).each do |column, value|
          connection.execute("UPDATE messages SET #{connection.quote_column_name(column)} = #{connection.quote(value)} WHERE id = 1")
        end
        if options["finished"]
          connection.execute("INSERT INTO ruby_llm_v2_backfills (task, completed) VALUES ('finished', 1)")
        end

        snapshot = -> do
          connection.tables.sort.to_h do |table|
            [table, {
              "columns" => connection.columns(table).map(&:name),
              "indexes" => connection.indexes(table).map(&:name).sort,
              "rows" => connection.select_all("SELECT * FROM #{connection.quote_table_name(table)}").to_a
            }]
          end
        end
        before = snapshot.call
        require ARGV.fetch(0)
        error = nil
        begin
          CleanupRubyLlmV2Upgrade.new.migrate(:up)
        rescue => exception
          error = exception.message
        end
        puts JSON.generate(before: before, after: snapshot.call, error: error)
      RUBY
    )
    expect(status.success?).to be(true), stderr
    JSON.parse(stdout)
  end

  def expect_native_records_preserved(result)
    before = result.fetch("before")
    after = result.fetch("after")
    native_columns = %w[id role content raw_content]
    expect(after.fetch("messages").fetch("rows")).to eq(
      before.fetch("messages").fetch("rows").map { |row| row.slice(*native_columns) }
    )
    %w[ruby_llm_tool_calls ruby_llm_usages].each do |table|
      expect(after.fetch(table)).to eq(before.fetch(table))
    end
  end

  it "cleans a schema-loaded database while preserving native messages, tool links and usage" do
    result = cleanup_result

    expect(result["error"]).to be_nil
    expect(result.fetch("after")).not_to have_key("ruby_llm_v2_backfills")
    expect(result.dig("after", "messages", "columns")).to eq(%w[id role content raw_content])
    expect_native_records_preserved(result)
  end

  it "also permits unused legacy columns when the progress table is absent" do
    result = cleanup_result(progress_table: false)

    expect(result["error"]).to be_nil
    expect_native_records_preserved(result)
  end

  it "cleans an empty schema without inventing completion markers" do
    result = cleanup_result(empty_messages: true)

    expect(result["error"]).to be_nil
    expect(result.fetch("after")).not_to have_key("ruby_llm_v2_backfills")
    expect(result.dig("after", "messages", "rows")).to eq([])
  end

  {
    model_id: 1, tool_call_id: 1, content_raw: "false", input_tokens: 0,
    output_tokens: 0, cached_tokens: 0, cache_creation_tokens: 0,
    cache_read_tokens: 0, cache_write_tokens: 0, thinking_tokens: 0,
    total_cost: 0, cost_details: "{}"
  }.each do |column, value|
    it "refuses unverified #{column} data before changing any schema or records" do
      result = cleanup_result(legacy_values: { column => value })

      expect(result["error"]).to include("BackfillRubyLlmV2Data", "FinishRubyLlmV2Upgrade")
      expect(result.fetch("after")).to eq(result.fetch("before"))
    end
  end

  it "refuses legacy data even when the progress table is missing" do
    result = cleanup_result(progress_table: false, legacy_values: { input_tokens: 0 })

    expect(result["error"]).to include("unverified legacy message data")
    expect(result.fetch("after")).to eq(result.fetch("before"))
  end

  it "retains the existing finished-marker path for verified legacy data" do
    result = cleanup_result(finished: true, legacy_values: { input_tokens: 42, total_cost: 0.125 })

    expect(result["error"]).to be_nil
    expect(result.fetch("after")).not_to have_key("ruby_llm_v2_backfills")
    expect_native_records_preserved(result)
  end

  it "continues to refuse copy-mode databases without altering them" do
    result = cleanup_result(copy_mode: true)

    expect(result["error"]).to include("--mode copy")
    expect(result.fetch("after")).to eq(result.fetch("before"))
  end
end
