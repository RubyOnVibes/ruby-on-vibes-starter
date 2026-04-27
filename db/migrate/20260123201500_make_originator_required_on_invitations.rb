class MakeOriginatorRequiredOnInvitations < ActiveRecord::Migration[8.1]
  def change
    change_column_null :invitations, :originator_id, false
  end
end
