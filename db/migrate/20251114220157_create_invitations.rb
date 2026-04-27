class CreateInvitations < ActiveRecord::Migration[8.1]
  def change
    create_table "invitations" do |t|
      t.string "name", null: false
      t.string "email", null: false
      t.bigint "account_id", null: false
      t.bigint "invited_by_id"
      t.json "roles", default: {}, null: false
      t.string "token", null: false
      t.timestamps

      t.index ["account_id", "email"], name: "index_account_invitations_on_account_id_and_email", unique: true
      t.index ["invited_by_id"], name: "index_account_invitations_on_invited_by_id"
      t.index ["token"], name: "index_account_invitations_on_token", unique: true
    end

    add_foreign_key "invitations", "accounts"
    add_foreign_key "invitations", "users", column: "invited_by_id"

    add_column "users", "invitations_count", :integer, default: 0, null: false
    add_index "users", "invitations_count"
  end
end
