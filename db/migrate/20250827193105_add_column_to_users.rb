class AddColumnToUsers < ActiveRecord::Migration[8.0]
  def change
    add_column :users, :gravatar_url, :string, null: false, default: ''
  end
end