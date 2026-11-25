class RenameOrganizationsToWorkspaces < ActiveRecord::Migration[8.1]
  def change
    # Rename the table
    rename_table :organizations, :workspaces if table_exists?(:organizations)

    # Rename the column in the workspaces table itself
    rename_column :workspaces, :is_team_organization, :is_team_workspace if column_exists?(:workspaces, :is_team_organization)

    # Rename foreign key columns in other tables
    rename_column :invitations, :organization_id, :workspace_id if column_exists?(:invitations, :organization_id)
    rename_column :members, :organization_id, :workspace_id if column_exists?(:members, :organization_id)
  end
end
