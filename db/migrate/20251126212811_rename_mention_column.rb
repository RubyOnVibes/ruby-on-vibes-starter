class RenameMentionColumn < ActiveRecord::Migration[8.1]
  def change
    rename_column :mentions, :model_name, :mentionable_type if column_exists?(:mentions, :model_name)
  end
end
