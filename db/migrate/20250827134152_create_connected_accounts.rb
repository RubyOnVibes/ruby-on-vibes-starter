class CreateConnectedAccounts < ActiveRecord::Migration[8.0]
  def change
    json_col_type = :json
    adapter_name = ActiveRecord::Base.connection.adapter_name.downcase
    if adapter_name.include?("postgres")
      json_col_type = :jsonb
    end

    create_table :connected_accounts do |t|
      t.string :provider, null: false, default: ''
      t.string :uid, null: false, default: ''
      t.string :refresh_token, null: false, default: ''
      t.datetime :expires_at, precision: nil      
      t.send(json_col_type, :auth, default: {}, null: false)
      t.string :access_token, null: false, default: ''
      t.string :access_token_secret, null: false, default: ''
      t.string :owner_type, null: false, default: ''
      t.bigint :owner_id, null: false
      t.timestamps
    end

    add_index :connected_accounts, [:owner_id, :owner_type]
  end
end
