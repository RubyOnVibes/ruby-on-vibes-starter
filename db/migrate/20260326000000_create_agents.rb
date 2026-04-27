class CreateAgents < ActiveRecord::Migration[8.0]
  def change
    create_table :agents do |t|
      t.references :workspace, null: false, foreign_key: true
      t.references :member, null: false, foreign_key: true
      t.references :chat, null: false, foreign_key: true
      t.string :name, null: false
      t.string :identifier, null: false
      t.text :instructions
      t.string :instructions_prompt
      t.json :tool_config
      t.string :schedule
      t.boolean :active, null: false, default: true
      t.string :webhook_token
      t.json :metadata, default: {}
      t.timestamps
    end

    add_index :agents, [:workspace_id, :identifier], unique: true
    add_index :agents, [:workspace_id, :active]
    add_index :agents, :webhook_token, unique: true
  end
end
