class CreateAgentDeliveries < ActiveRecord::Migration[8.1]
  def change
    create_table :agent_deliveries do |t|
      t.references :agent, null: false, foreign_key: true
      t.references :chat, null: false, foreign_key: true
      t.references :initiated_by_member, foreign_key: { to_table: :members }
      t.references :input_message, foreign_key: { to_table: :messages }, index: { unique: true }
      t.references :chat_run, foreign_key: true, index: { unique: true }
      t.string :trigger, null: false
      t.string :idempotency_key
      t.string :payload_digest, null: false
      t.string :event_type
      t.text :payload, null: false, default: ""
      t.integer :status, null: false, default: 0
      t.string :rejection_reason
      t.datetime :next_attempt_at
      t.timestamps
    end
    add_index :agent_deliveries, [:agent_id, :trigger, :idempotency_key], unique: true
    add_index :agent_deliveries, [:status, :next_attempt_at]
  end
end
