class AddTriggerToAgentTasks < ActiveRecord::Migration[8.0]
  def change
    add_column :agent_tasks, :trigger, :string, null: false, default: "chat"
  end
end
