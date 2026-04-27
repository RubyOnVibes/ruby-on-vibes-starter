# frozen_string_literal: true

class AddHasMultipleMembersToChats < ActiveRecord::Migration[8.1]
  def change
    add_column :chats, :has_multiple_members, :boolean, default: false, null: false
    add_index :chats, :has_multiple_members
  end
end
