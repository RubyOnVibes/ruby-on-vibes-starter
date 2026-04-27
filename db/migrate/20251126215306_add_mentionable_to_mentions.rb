class AddMentionableToMentions < ActiveRecord::Migration[8.1]
  def up
    # Add mentionable_id as nullable first
    add_column :mentions, :mentionable_id, :integer
    
    # Populate from sgid using Ruby
    reversible do |dir|
      dir.up do
        Mention.reset_column_information
        Mention.find_each do |mention|
          begin
            resolved = GlobalID::Locator.locate_signed(mention.sgid, for: 'attachable')
            mention.update_column(:mentionable_id, resolved.id) if resolved
          rescue => e
            Rails.logger.warn "Could not resolve mention #{mention.id}: #{e.message}"
          end
        end
      end
    end
    
    # Now make it NOT NULL
    change_column_null :mentions, :mentionable_id, false
    add_index :mentions, [:mentionable_type, :mentionable_id]
  end
  
  def down
    remove_index :mentions, [:mentionable_type, :mentionable_id]
    remove_column :mentions, :mentionable_id
  end
end
