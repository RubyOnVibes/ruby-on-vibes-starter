class RenameInvitedByToOriginatorOnInvitations < ActiveRecord::Migration[8.1]
  def change
    rename_column :invitations, :invited_by_id, :originator_id
    rename_index :invitations, :index_account_invitations_on_invited_by_id, :index_invitations_on_originator_id
  end
end