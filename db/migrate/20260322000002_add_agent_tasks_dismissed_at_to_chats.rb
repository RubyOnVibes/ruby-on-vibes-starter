# frozen_string_literal: true

class AddAgentTasksDismissedAtToChats < ActiveRecord::Migration[8.0]
  def change
    add_column :chats, :agent_tasks_dismissed_at, :datetime
  end
end
