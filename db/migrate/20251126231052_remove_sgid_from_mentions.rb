class RemoveSgidFromMentions < ActiveRecord::Migration[8.1]
  def change
    remove_column :mentions, :sgid, :string
  end
end
