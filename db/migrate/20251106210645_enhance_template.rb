class EnhanceTemplate < ActiveRecord::Migration[8.1]
  def change
    # Account/AccountUser
    add_reference :accounts, :owner, null: false, foreign_key: { to_table: :users }, index: true
    add_column :accounts, :account_users_count, :integer, default: 0
    add_column :accounts, :is_team_account, :boolean, default: true, null: false
    add_column :account_users, :admin, :boolean, default: false, null: false
    add_column :account_users, :roles, :json, null: false, default: {}

    # Chat/Message/Model/ToolCall
    remove_column :chats, :model_id_string, :string if column_exists?(:chats, :model_id_string)
    remove_column :messages, :model_id_string, :string if column_exists?(:messages, :model_id_string)
    
    change_column_null :messages, :role, false
    add_index :messages, :role, if_not_exists: true
    
    remove_index :tool_calls, :tool_call_id, if_exists: true
    add_index :tool_calls, :tool_call_id, unique: true, if_not_exists: true
    
    add_foreign_key :messages, :tool_calls, if_not_exists: true
  end
end
