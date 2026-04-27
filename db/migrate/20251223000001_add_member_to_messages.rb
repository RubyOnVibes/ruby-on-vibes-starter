# frozen_string_literal: true

class AddMemberToMessages < ActiveRecord::Migration[8.0]
  def change
    add_column :messages, :member_id, :integer
    add_index :messages, :member_id
    add_foreign_key :messages, :members
  end
end

