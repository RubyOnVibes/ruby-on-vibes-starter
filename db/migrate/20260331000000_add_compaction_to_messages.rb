# frozen_string_literal: true

class AddCompactionToMessages < ActiveRecord::Migration[8.0]
  def change
    add_column :messages, :compacted, :boolean, null: false, default: false
    add_column :chats, :compaction_summary, :text
    add_column :chats, :last_compacted_at, :datetime
    add_column :chats, :compaction_token_threshold, :integer
    add_column :chats, :compacting_since, :datetime
    add_index :messages, [:chat_id, :compacted]
  end
end
