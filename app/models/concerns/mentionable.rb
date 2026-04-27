# frozen_string_literal: true

##
# Mentionable - Make models taggable in chat with @mentions
#
# Include this concern to make a model mentionable in chat.
# The controller handles search logic; this concern handles serialization.
#
#   class Project < ApplicationRecord
#     include Mentionable
#
#     # Optional: Override for custom display
#     def mentionable_label
#       name
#     end
#
#     def mentionable_summary
#       "#{tasks.count} tasks, #{status}"
#     end
#   end
#
# Override these instance methods for customization:
#   - mentionable_label: Display name for @mentions (default: name/title/email)
#   - mentionable_path: URL path for linking (default: polymorphic_path)
#   - mentionable_kind: Type identifier for UI (default: model_name.underscore)
#   - mentionable_summary: Brief summary for LLM context (default: label)
#
module Mentionable
  extend ActiveSupport::Concern

  ##
  # Display label for this mention
  # Override in model for custom display
  #
  # @return [String] Display label
  #
  def mentionable_label
    %i[username name title].each do |method|
      return send(method) if respond_to?(method) && send(method).present?
    end

    to_s
  end

  ##
  # Kind identifier for UI rendering (icon, color, etc.)
  # Override in model for custom kinds
  #
  # @return [Symbol] Kind identifier
  #
  def mentionable_kind
    self.class.name.underscore.to_sym
  end

  ##
  # Path for navigating to this mentionable
  # Override in model for custom routing
  #
  # @return [String] URL path
  #
  def mentionable_path
    Rails.application.routes.url_helpers.polymorphic_path(self)
  rescue NoMethodError, ArgumentError
    "/#{self.class.name.underscore.pluralize}/#{respond_to?(:to_param) ? to_param : id}"
  end

  ##
  # Serialize for mention autocomplete/display
  # Used by frontend for rendering mention chips
  #
  # @return [Hash] Mention data
  #
  def to_mention
    {
      id: respond_to?(:to_param) ? to_param : id.to_s,
      model: self.class.name,
      label: mentionable_label,
      kind: mentionable_kind,
      path: mentionable_path
    }
  end

  ##
  # Structured LLM context (schema-based)
  # Returns RecordContext instance if defined, falls back to simple hash
  #
  # @return [RecordContext, Hash] Structured context for LLM
  #
  def to_llm_context
    context_class = Mentionables.context_class_for(self.class)

    if context_class
      context_class.from_record(self)
    else
      to_llm_mention
    end
  end

  ##
  # Lightweight LLM context for inline mention resolution
  # Used by Message#resolve_mentions_for_llm to enrich @mention placeholders
  # Also serves as fallback for to_llm_context when no RecordContext exists
  #
  # @return [Hash] Lightweight context with type, id, label, summary
  #
  def to_llm_mention
    {
      type: self.class.name,
      id: respond_to?(:to_param) ? to_param : id,
      label: mentionable_label,
      summary: mentionable_summary
    }
  end

  ##
  # Brief summary of this record for LLM context
  # Override in model for rich context (keep concise for tokens)
  #
  # @return [String] Brief summary for LLM context
  #
  def mentionable_summary
    mentionable_label
  end
end
