class UpdateUsers < ActiveRecord::Migration[8.0]
  def change
    json_col_type = :json
    adapter_name = ActiveRecord::Base.connection.adapter_name.downcase
    if adapter_name.include?("postgres")
      json_col_type = :jsonb
    end

    add_column :users, :preferences, json_col_type, default: {}, null: false
    add_column :users, :first_name, :string, null: false, default: ''
    add_column :users, :last_name, :string, null: false, default: ''
    add_column :users, :time_zone, :string, null: false, default: 'UTC'
    add_column :users, :admin, :boolean, null: false, default: false
  end
end
