class AddUserSubmittedToMessages < ActiveRecord::Migration[8.1]
  def change
    add_column :messages, :user_submitted, :boolean, default: false, null: false
    add_index :messages, :user_submitted
  end
end
