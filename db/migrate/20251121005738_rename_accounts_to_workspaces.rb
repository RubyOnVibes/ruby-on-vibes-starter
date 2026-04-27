class RenameAccountsToWorkspaces < ActiveRecord::Migration[8.0]
  def change
    # Rename accounts table to workspaces
    rename_table :accounts, :workspaces
    
    # Rename account_users table to members
    rename_table :account_users, :members
    
    # Rename all account_id foreign keys to workspace_id
    rename_column :members, :account_id, :workspace_id
    rename_column :invitations, :account_id, :workspace_id
    rename_column :workspaces, :account_users_count, :members_count
  end
end
