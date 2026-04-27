# frozen_string_literal: true

class AddNameToChats < ActiveRecord::Migration[8.0]
  def change
    add_column :chats, :name, :string, null: false, default: ''
    add_index :chats, :name
  end
end

