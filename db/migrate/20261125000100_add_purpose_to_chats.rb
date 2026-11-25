class AddPurposeToChats < ActiveRecord::Migration[8.1]
  def change
    add_column :chats, :purpose, :string, default: "assistant", null: false
  end
end
