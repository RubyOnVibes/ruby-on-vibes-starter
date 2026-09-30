class CreateModels < ActiveRecord::Migration[8.0]
  def change
    create_table :models do |t|
      t.string :model_id, null: false
      t.string :name, null: false
      t.string :provider, null: false
      t.string :family
      t.datetime :model_created_at
      t.integer :context_window
      t.integer :max_output_tokens
      t.date :knowledge_cutoff

      t.json :modalities, default: {}
      t.json :capabilities, default: []
      t.json :pricing, default: {}
      t.json :metadata, default: {}

      t.timestamps

      t.index [:provider, :model_id], unique: true
      t.index :provider
      t.index :family

    end

    # Load models from JSON
    say_with_time "Loading models from models.json" do
      models = Class.new(ActiveRecord::Base) do
        self.table_name = "models"
        self.inheritance_column = :_type_disabled
      end

      RubyLLM.models.load_from_json.each do |model_info|
        models.create!(
          model_id: model_info.id,
          name: model_info.name,
          provider: model_info.provider,
          family: model_info.family,
          model_created_at: model_info.created_at,
          context_window: model_info.context_window,
          max_output_tokens: model_info.max_output_tokens,
          knowledge_cutoff: model_info.knowledge_cutoff,
          modalities: model_info.modalities.to_h,
          capabilities: model_info.capabilities,
          pricing: model_info.pricing.to_h,
          metadata: model_info.metadata
        )
      end
    end
  end
end
