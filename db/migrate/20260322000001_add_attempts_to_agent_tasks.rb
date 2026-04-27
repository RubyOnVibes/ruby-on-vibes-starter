# frozen_string_literal: true

class AddAttemptsToAgentTasks < ActiveRecord::Migration[8.0]
  def change
    add_column :agent_tasks, :attempts, :integer, default: 0, null: false
  end
end
