class AddCompletionTimestampsToChatRuns < ActiveRecord::Migration[8.0]
  def change
    add_column :chat_runs, :completed_at, :datetime
    add_column :chat_runs, :failed_at, :datetime
    
    # Note: cancelled_at already exists from original migration
  end
end

