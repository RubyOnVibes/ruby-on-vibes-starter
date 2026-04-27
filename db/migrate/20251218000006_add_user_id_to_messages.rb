# frozen_string_literal: true

class AddUserIdToMessages < ActiveRecord::Migration[8.1]
  def change
    add_reference :messages, :user, null: true, foreign_key: true, index: true
    
    # Backfill user_id for existing user_submitted messages
    # Match message.chat.member.user_id
    reversible do |dir|
      dir.up do
        execute <<-SQL
          UPDATE messages
          SET user_id = (
            SELECT members.user_id
            FROM chats
            INNER JOIN members ON members.id = chats.member_id
            WHERE chats.id = messages.chat_id
          )
          WHERE role = 'user' AND user_submitted = true
        SQL
      end
    end
  end
end
