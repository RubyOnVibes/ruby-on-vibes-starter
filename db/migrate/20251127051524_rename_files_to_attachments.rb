# frozen_string_literal: true

class RenameFilesToAttachments < ActiveRecord::Migration[8.0]
  def change
    # Rename Active Storage attachment association from 'files' to 'attachments'
    # This is required for ruby_llm's automatic multimodal support
    # ruby_llm's MessageMethods#extract_content specifically looks for 'attachments'
    
    # Active Storage uses a polymorphic 'record' association, so we just need to update the name
    # The 'name' column in active_storage_attachments stores the association name
    ActiveStorage::Attachment.where(record_type: 'Message', name: 'files').update_all(name: 'attachments')
  end
end
