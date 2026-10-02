# frozen_string_literal: true

class AddApprovalAndUsageToChatRuns < ActiveRecord::Migration[8.1]
  def change
    add_reference :chat_runs, :initiated_by_member, foreign_key: { to_table: :members }

    add_column :chat_runs, :llm_attempts, :integer, null: false, default: 0
    add_column :chat_runs, :input_tokens, :integer
    add_column :chat_runs, :output_tokens, :integer
    add_column :chat_runs, :cache_read_tokens, :integer
    add_column :chat_runs, :cache_write_tokens, :integer
    add_column :chat_runs, :thinking_tokens, :integer
    add_column :chat_runs, :total_cost, :decimal, precision: 16, scale: 10
    add_column :chat_runs, :usage_metadata, :json, null: false, default: {}

    remove_index :chat_runs, name: "index_chat_runs_on_chat_active"
    add_index :chat_runs, :chat_id,
      unique: true,
      where: "status IN (0, 1, 5, 6)",
      name: "index_chat_runs_on_chat_active"
  end
end
