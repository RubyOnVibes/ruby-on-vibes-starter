class AddSkipLlmContextToMessages < ActiveRecord::Migration[8.0]
  def change
    add_column :messages, :skip_llm_context, :boolean, default: false, null: false
  end
end
