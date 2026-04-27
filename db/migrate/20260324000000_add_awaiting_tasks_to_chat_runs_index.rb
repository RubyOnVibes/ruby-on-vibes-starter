# frozen_string_literal: true

class AddAwaitingTasksToChatRunsIndex < ActiveRecord::Migration[8.0]
  def change
    # Remove the old unique index that only covers pending (0) and running (1)
    remove_index :chat_runs, name: 'index_chat_runs_on_chat_active'

    # Add new unique index that also covers awaiting_tasks (5)
    # Only ONE active run per chat at a time (pending, running, or awaiting_tasks)
    add_index :chat_runs, :chat_id,
      unique: true,
      where: "status IN (0, 1, 5)",
      name: 'index_chat_runs_on_chat_active'
  end
end
