class AddMemberToChats < ActiveRecord::Migration[8.0]
  def change
    # Add member_id to chats for multitenancy (personal + team chats)
    # Members bridge Users + Workspaces
    add_reference :chats, :member, null: true, foreign_key: true
    
    # Also add ai_processing flag for UI state
    add_column :messages, :ai_processing, :boolean, default: false
    add_column :messages, :metadata, :jsonb, default: {}
    
    add_index :messages, [:chat_id, :ai_processing], unique: true, where: "ai_processing = true"
  end
end

