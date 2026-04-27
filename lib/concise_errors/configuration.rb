# frozen_string_literal: true

module ConciseErrors
  # Stores global configuration for the middleware.
  class Configuration
    DEFAULT_STACK_LINES = 10
    DEFAULT_FORMAT = :text

    attr_accessor :stack_trace_lines, :enabled, :logger, :application_root, :cleaner, :full_error_param, :enable_in_production

    def initialize
      reset!
    end

    def format
      (@format || DEFAULT_FORMAT).to_sym
    end

    def enabled?
      enabled != false
    end

    def enable_in_production?
      enable_in_production == true
    end

    def format=(value)
      @format = value&.to_sym
    end

    def reset!
      @format = :text
      @stack_trace_lines = DEFAULT_STACK_LINES
      @enabled = true
      @logger = nil
      @application_root = nil
      @cleaner = nil
      @full_error_param = "concise_errors_full"
      @enable_in_production = false
    end
  end
end
