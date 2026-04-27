# frozen_string_literal: true

class CreateChatRuns < ActiveRecord::Migration[8.0]
  def change
    drop_table :chat_runs if table_exists?(:chat_runs)

    create_table :chat_runs do |t|
      t.references :chat, null: false, foreign_key: true
      t.references :assistant_message, foreign_key: { to_table: :messages }
      
      t.integer :status, default: 0, null: false
      
      t.datetime :cancelled_at
      t.string :cancelled_by
      t.string :node_name    # Track which node is running this job (multi-node safety)
      
      t.timestamps
    end
    
    add_index :chat_runs, [:chat_id, :status]
    add_index :chat_runs, :status
    
    # CRITICAL: Prevent duplicate active runs per chat
    # Only ONE pending or running run per chat at a time
    # Allows multiple completed/failed/cancelled runs (for history)
    add_index :chat_runs, :chat_id,
      unique: true,
      where: "status IN (0, 1)",  # 0=pending, 1=running
      name: 'index_chat_runs_on_chat_active'
  end
end

