# frozen_string_literal: true

class BackfillHasMultipleMembers < ActiveRecord::Migration[8.1]
  def up
    # Set has_multiple_members = true for chats with more than 1 member
    execute <<-SQL
      UPDATE chats
      SET has_multiple_members = true
      WHERE id IN (
        SELECT chat_id
        FROM chat_members
        GROUP BY chat_id
        HAVING COUNT(*) > 1
      )
    SQL
    
    # Set has_multiple_members = false for chats with exactly 1 member (default, but explicit)
    execute <<-SQL
      UPDATE chats
      SET has_multiple_members = false
      WHERE id IN (
        SELECT chat_id
        FROM chat_members
        GROUP BY chat_id
        HAVING COUNT(*) = 1
      )
    SQL
  end

  def down
    # Reset all to false
    execute "UPDATE chats SET has_multiple_members = false"
  end
end
