class AddUserToChats < ActiveRecord::Migration[8.0]
  def change
    # Preserve the original user reference. Workspace membership is added by
    # AddMemberToChats after the account_users table has been renamed.
    add_reference :chats, :user, null: true, foreign_key: true
    
    # Also add ai_processing flag for UI state
    add_column :messages, :ai_processing, :boolean, default: false
    add_column :messages, :metadata, :json, default: {}
    
    add_index :messages, [:chat_id, :ai_processing], unique: true, where: "ai_processing = true"
  end
end
