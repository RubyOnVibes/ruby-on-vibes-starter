# frozen_string_literal: true

class FixChatInvitationsUniqueness < ActiveRecord::Migration[8.0]
  def change
    # Remove old unique index (prevents re-inviting ignored users)
    remove_index :chat_invitations, 
                 column: [:chat_id, :invitee_id],
                 name: "index_chat_invitations_on_chat_id_and_invitee_id"
    
    # Add partial unique index - only enforces uniqueness for pending OR accepted
    # This allows unlimited ignored invitations (status = 2)
    add_index :chat_invitations, 
              [:chat_id, :invitee_id],
              unique: true,
              where: "status IN (0, 1)",
              name: "index_chat_invitations_on_chat_invitee_active"
  end
end
