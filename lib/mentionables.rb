# frozen_string_literal: true

##
# Mentionables - Registry for @mentionable models
#
# Provides discovery of models that include the Mentionable concern.
# Search logic lives in the controller, not here.
#
# Usage:
#   Mentionables.all                        # All mentionable model classes
#   Mentionables.registered?(Member)        # Check if model is mentionable
#   Mentionables.context_class_for(Chat)    # Get ChatContext class
#
module Mentionables
  class << self
    ##
    # All model classes that include Mentionable
    #
    # @return [Array<Class>] Mentionable model classes
    #
    def all
      @all ||= discover_mentionable_models
    end

    ##
    # Clear cached models (for testing/reloading)
    #
    def reset!
      @all = nil
    end

    ##
    # Check if a model class is mentionable
    #
    # @param model_class [Class] The model class to check
    # @return [Boolean] True if model includes Mentionable
    #
    def registered?(model_class)
      all.include?(model_class)
    end

    ##
    # Get context class for a model (auto-discovery)
    #
    # @param model_class [Class] The model class (e.g., Chat)
    # @return [Class, nil] The context class (e.g., ChatContext) or nil
    #
    # @example
    #   Mentionables.context_class_for(Chat)   # => ChatContext
    #   Mentionables.context_class_for(Member) # => MemberContext
    #
    def context_class_for(model_class)
      "#{model_class.name}Context".safe_constantize
    end

    private

    def discover_mentionable_models
      # Eager load all models in production (already loaded)
      # In development, this triggers autoloading
      Rails.application.eager_load! if Rails.env.development?

      ApplicationRecord.descendants.select do |klass|
        klass.include?(Mentionable)
      end
    rescue StandardError => e
      Rails.logger.warn "[Mentionables] Discovery failed: #{e.message}"
      []
    end
  end
end