class RenameMentionColumns < ActiveRecord::Migration[8.1]
  def up
    # Remove old indexes
    remove_index :mentions, column: :kind if index_exists?(:mentions, :kind)
    remove_index :mentions, column: [ :message_id, :path ] if index_exists?(:mentions, [ :message_id, :path ])

    # Rename columns
    rename_column :mentions, :path, :sgid if column_exists?(:mentions, :path)
    rename_column :mentions, :kind, :mentionable_type if column_exists?(:mentions, :kind)

    # Add metadata column
    add_column :mentions, :metadata, :text, default: "{}" unless column_exists?(:mentions, :metadata)

    # Add new indexes
    add_index :mentions, :sgid unless index_exists?(:mentions, :sgid)
    add_index :mentions, :mentionable_type unless index_exists?(:mentions, :mentionable_type)
    add_index :mentions, [ :message_id, :sgid ] unless index_exists?(:mentions, [ :message_id, :sgid ])
  end

  def down
    # Remove new indexes
    remove_index :mentions, column: :sgid
    remove_index :mentions, column: :mentionable_type
    remove_index :mentions, column: [ :message_id, :sgid ]

    # Remove metadata column
    remove_column :mentions, :metadata

    # Rename columns back
    rename_column :mentions, :sgid, :path
    rename_column :mentions, :mentionable_type, :kind

    # Add old indexes back
    add_index :mentions, :kind
    add_index :mentions, [ :message_id, :path ]
  end
end
