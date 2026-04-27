class RenameOrganizationsToWorkspaces < ActiveRecord::Migration[8.1]
  def change
    # Rename the table
    rename_table :organizations, :workspaces
    
    # Rename the column in the workspaces table itself
    rename_column :workspaces, :is_team_organization, :is_team_workspace
    
    # Rename foreign key columns in other tables
    rename_column :invitations, :organization_id, :workspace_id
    rename_column :members, :organization_id, :workspace_id
  end
end
