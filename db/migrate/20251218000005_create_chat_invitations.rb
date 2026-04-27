# frozen_string_literal: true

class CreateChatInvitations < ActiveRecord::Migration[8.1]
  def change
    create_table :chat_invitations do |t|
      t.references :chat, null: false, foreign_key: true, index: true
      t.references :inviter, null: false, foreign_key: { to_table: :members }, index: true
      t.references :invitee, null: false, foreign_key: { to_table: :members }, index: true
      t.integer :status, default: 0, null: false  # 0=pending, 1=accepted, 2=ignored
      t.datetime :responded_at

      t.timestamps
    end

    # Ensure each member can only be invited once per chat
    add_index :chat_invitations, [:chat_id, :invitee_id], unique: true
    
    # Fast filtering by status
    add_index :chat_invitations, [:status, :invitee_id]
  end
end
