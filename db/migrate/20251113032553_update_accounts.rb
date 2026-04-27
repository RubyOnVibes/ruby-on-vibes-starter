class UpdateAccounts < ActiveRecord::Migration[8.1]
  def change
    add_column :accounts, :billing_email, :string, null: false, default: ''
    add_column :accounts, :extra_billing_info, :string, null: false, default: ''

    create_table "plans", force: :cascade do |t|
      t.string "name", null: false, default: ''
      t.integer "amount", null: false, default: 0
      t.string "unit_label"
      t.boolean "charge_per_unit", null: false, default: false
      t.string "interval", null: false
      t.integer "interval_count", default: 1
      t.integer "trial_period_days", default: 0, null: false
      t.string "stripe_id"
      t.string "lemon_squeezy_id"
      t.string "braintree_id"
      t.string "fake_processor_id"
      t.boolean "hidden", null: false, default: false
      t.string "contact_url", null: false, default: ''
      t.datetime "created_at", precision: nil, null: false
      t.string "currency"
      t.string "description", null: false, default: ''
      t.json "metadata", null: false, default: {}
      t.datetime "updated_at", precision: nil, null: false
    end
  end
end
