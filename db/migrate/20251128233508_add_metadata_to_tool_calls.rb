class AddMetadataToToolCalls < ActiveRecord::Migration[8.1]
  def change
    add_column :tool_calls, :metadata, :json, default: {}, null: false
  end
end
