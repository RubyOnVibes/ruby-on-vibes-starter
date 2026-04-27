# frozen_string_literal: true

class BackfillChatMembersFromExistingChats < ActiveRecord::Migration[8.1]
  def up
    # Backfill: create owner chat_member for each existing chat
    # Use chat.created_at for historical accuracy (when owner created = when they joined)
    execute <<-SQL
      INSERT INTO chat_members (chat_id, member_id, role, created_at, updated_at)
      SELECT 
        id as chat_id,
        member_id,
        0 as role,  -- owner
        created_at as created_at,  -- Preserve historical join time
        CURRENT_TIMESTAMP as updated_at
      FROM chats
      WHERE member_id IS NOT NULL
      ON CONFLICT (chat_id, member_id) DO NOTHING
    SQL
  end

  def down
    # Remove backfilled records
    execute <<-SQL
      DELETE FROM chat_members
      WHERE role = 0  -- Only remove owner records
    SQL
  end
end
