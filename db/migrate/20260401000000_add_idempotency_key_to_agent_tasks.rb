# frozen_string_literal: true

class AddIdempotencyKeyToAgentTasks < ActiveRecord::Migration[8.0]
  def change
    add_column :agent_tasks, :idempotency_key, :string
    add_index :agent_tasks, [:chat_id, :idempotency_key], unique: true, name: "index_agent_tasks_on_chat_id_and_idempotency_key"
  end
end
