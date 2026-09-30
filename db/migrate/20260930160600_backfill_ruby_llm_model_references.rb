# frozen_string_literal: true

class BackfillRubyLlmModelReferences < ActiveRecord::Migration[8.1]
  def up
    return unless table_exists?(:models) && table_exists?(:chats) && table_exists?(:messages)

    model_info = RubyLLM.models.find(RubyLLM.config.default_model)
    model = legacy_models.find_or_initialize_by(
      model_id: model_info.id,
      provider: model_info.provider
    )
    model.assign_attributes(model_attributes(model_info, model))
    model.save!

    chat_ids = legacy_messages.where(role: "assistant").select(:chat_id)
    legacy_chats.where(id: chat_ids, model_id: nil).update_all(model_id: model.id)
  rescue RubyLLM::ModelNotFoundError => error
    raise ActiveRecord::MigrationError,
      "Could not resolve the configured RubyLLM default model: #{error.message}"
  end

  def down
    # Historical model attribution cannot be safely distinguished from
    # references that were already present before this migration.
  end

  private

  def model_attributes(model_info, model)
    available = model.class.column_names
    {
      name: model_info.name,
      family: model_info.family,
      context_window: model_info.context_window,
      max_output_tokens: model_info.max_output_tokens,
      model_created_at: model_info.created_at,
      knowledge_cutoff: model_info.knowledge_cutoff,
      modalities: model_info.modalities&.to_h,
      capabilities: model_info.capabilities,
      pricing: model_info.pricing&.to_h,
      metadata: model_info.metadata
    }.select { |key, _value| available.include?(key.to_s) }
  end

  def legacy_models
    @legacy_models ||= migration_record(:models)
  end

  def legacy_chats
    @legacy_chats ||= migration_record(:chats)
  end

  def legacy_messages
    @legacy_messages ||= migration_record(:messages)
  end

  def migration_record(table)
    Class.new(ActiveRecord::Base) do
      self.table_name = table.to_s
      self.inheritance_column = :_type_disabled
    end
  end
end
