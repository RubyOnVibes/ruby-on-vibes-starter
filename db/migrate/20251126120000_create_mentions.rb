# frozen_string_literal: true

class CreateMentions < ActiveRecord::Migration[8.0]
  def change
    create_table :mentions do |t|
      t.references :message, null: false, foreign_key: true
      t.string :sgid, null: false              # GlobalID reference
      t.string :mentionable_type, null: false  # 'Chat', 'User', etc.
      t.string :label, null: false             # Display label
      t.jsonb :metadata, default: {}           # Extra data

      t.timestamps
    end
    
    add_index :mentions, :sgid
    add_index :mentions, :mentionable_type
    add_index :mentions, [:message_id, :sgid]
  end
end

