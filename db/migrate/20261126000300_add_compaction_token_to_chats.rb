class AddCompactionTokenToChats < ActiveRecord::Migration[8.1]
  def change
    add_column :chats, :compaction_token, :string
  end
end
