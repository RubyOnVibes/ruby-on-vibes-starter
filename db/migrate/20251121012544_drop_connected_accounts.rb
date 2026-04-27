class DropConnectedAccounts < ActiveRecord::Migration[8.1]
  def change
    drop_table :connected_accounts
  end
end
