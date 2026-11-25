class AddDurableDispatchToChatRuns < ActiveRecord::Migration[8.1]
  def change
    add_reference :chat_runs, :input_message, foreign_key: { to_table: :messages, on_delete: :nullify }
    add_column :chat_runs, :execution_options, :json, default: {}, null: false
    add_column :chat_runs, :resume_at, :datetime
    add_column :chat_runs, :trigger, :string, default: "user", null: false
    add_index :chat_runs, [:status, :resume_at]
  end
end
