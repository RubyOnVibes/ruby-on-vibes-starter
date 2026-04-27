class RemoveAiProcessingFromMessages < ActiveRecord::Migration[8.0]
  def change
    remove_index :messages, [:chat_id, :ai_processing], if_exists: true
    remove_column :messages, :ai_processing, :boolean, default: false
  end
end
