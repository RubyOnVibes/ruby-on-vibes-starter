# frozen_string_literal: true

class CreateAgentTaskEffects < ActiveRecord::Migration[8.0]
  def change
    create_table :agent_task_effects do |t|
      t.references :agent_task, null: false, foreign_key: true
      t.string :action, null: false
      t.references :target, polymorphic: true, null: true
      t.string :description, null: false
      t.json :details, default: {}
      t.timestamps
    end

    add_index :agent_task_effects, [:agent_task_id, :created_at]
    add_index :agent_task_effects, :action
  end
end
