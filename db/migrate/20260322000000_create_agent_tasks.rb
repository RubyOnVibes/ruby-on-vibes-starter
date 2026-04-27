# frozen_string_literal: true

class CreateAgentTasks < ActiveRecord::Migration[8.0]
  def change
    create_table :agent_tasks do |t|
      t.references :chat, null: false, foreign_key: true
      t.references :workspace, null: false, foreign_key: true
      t.references :member, null: false, foreign_key: true
      t.references :parent_task, foreign_key: { to_table: :agent_tasks }
      t.string :kind, null: false
      t.integer :status, null: false, default: 0
      t.integer :progress, default: 0
      t.string :progress_text
      t.json :metadata, default: {}
      t.json :result, default: {}
      t.text :error_message
      t.datetime :started_at
      t.datetime :completed_at
      t.timestamps
    end

    add_index :agent_tasks, [:workspace_id, :status]
    add_index :agent_tasks, [:chat_id, :status]
  end
end
