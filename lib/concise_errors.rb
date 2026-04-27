# frozen_string_literal: true

require "active_support"
require "active_support/core_ext/module/attribute_accessors"

require_relative "concise_errors/version"
require_relative "concise_errors/configuration"
require_relative "concise_errors/formatter"
require_relative "concise_errors/debug_exceptions"
require_relative "concise_errors/show_exceptions"

# ConciseErrors exposes configuration helpers and loads the custom error middleware.
module ConciseErrors
  class << self
    def configuration
      @configuration ||= Configuration.new
    end

    def configure
      yield(configuration)
    end

    def reset_configuration!
      @configuration = Configuration.new
    end

    def logger
      configuration.logger
    end

    def logger=(logger)
      configuration.logger = logger
    end

    def application_root
      configuration.application_root
    end

    def application_root=(path)
      configuration.application_root = path
    end

    def cleaner
      configuration.cleaner
    end

    def cleaner=(cleaner)
      configuration.cleaner = cleaner
    end
  end
end

require_relative "concise_errors/railtie" if defined?(Rails::Railtie)
