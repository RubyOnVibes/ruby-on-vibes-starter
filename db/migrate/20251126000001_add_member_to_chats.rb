class AddMemberToChats < ActiveRecord::Migration[8.0]
  def change
    # Add member_id to chats for multitenancy (personal + team chats)
    # Members bridge Users + Workspaces
    add_reference :chats, :member, null: true, foreign_key: true unless column_exists?(:chats, :member_id)
    
    # Also add ai_processing flag for UI state (check if exists)
    add_column :messages, :ai_processing, :boolean, default: false unless column_exists?(:messages, :ai_processing)
    add_column :messages, :metadata, :json, default: {} unless column_exists?(:messages, :metadata)
    
    unless index_exists?(:messages, [:chat_id, :ai_processing], unique: true, where: "ai_processing = true")
      add_index :messages, [:chat_id, :ai_processing], unique: true, where: "ai_processing = true"
    end
  end
end

