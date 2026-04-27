class RemoveLabelFromMentions < ActiveRecord::Migration[8.1]
  def change
    remove_column :mentions, :label, :string
  end
end
