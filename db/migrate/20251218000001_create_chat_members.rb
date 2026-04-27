# frozen_string_literal: true

class CreateChatMembers < ActiveRecord::Migration[8.1]
  def change
    create_table :chat_members do |t|
      t.references :chat, null: false, foreign_key: true, index: true
      t.references :member, null: false, foreign_key: true, index: true
      t.integer :role, null: false, default: 1  # 0 = owner, 1 = member
      t.datetime :last_read_at  # For future read receipts

      t.timestamps
    end

    # Ensure each member can only be added to a chat once
    add_index :chat_members, [:chat_id, :member_id], unique: true
    
    # Ensure each chat has exactly one owner (enforced at DB level)
    add_index :chat_members, :chat_id, 
      unique: true, 
      where: "role = 0",
      name: "index_chat_members_on_chat_id_unique_owner"
  end
end