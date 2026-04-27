class UpdateDb < ActiveRecord::Migration[8.1]
  def change
    rename_column :workspaces, :is_team_account, :is_team_organization
  end
end
