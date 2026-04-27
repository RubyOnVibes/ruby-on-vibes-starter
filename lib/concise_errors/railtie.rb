# frozen_string_literal: true

require "rails/railtie"

module ConciseErrors
  # Integrates the middleware with a host Rails application.
  class Railtie < Rails::Railtie
    config.concise_errors = ConciseErrors.configuration

    initializer "concise_errors.configure_defaults" do |app|
      ConciseErrors.configure do |config|
        apply_framework_defaults(config, app)
      end
    end

    initializer "concise_errors.swap_middleware", before: :build_middleware_stack do |app|
      next unless ConciseErrors.configuration.enabled?

      stack = app.config.middleware

      # Swap DebugExceptions for development/local requests
      disable_web_console(stack)

      # Ensure ActionDispatch::DebugExceptions exists before trying to swap
      stack.use ::ActionDispatch::DebugExceptions

      begin
        stack.swap ::ActionDispatch::DebugExceptions, ConciseErrors::DebugExceptions
        stack.delete ::ActionDispatch::DebugExceptions
      rescue RuntimeError
        stack.delete ::ActionDispatch::DebugExceptions
        stack.use ConciseErrors::DebugExceptions
      end

      # Swap ShowExceptions for production errors if enabled
      if ConciseErrors.configuration.enable_in_production?
        swap_show_exceptions(stack)
      end
    end

    private

    def apply_framework_defaults(config, app)
      config.logger ||= detect_logger
      config.application_root ||= detect_root(app)
      config.format = detect_format if config.format == Configuration::DEFAULT_FORMAT
      config.stack_trace_lines ||= Configuration::DEFAULT_STACK_LINES
      config.cleaner ||= detect_cleaner
    end

    def detect_logger
      return Rails.logger if defined?(Rails) && Rails.respond_to?(:logger)

      require "logger"
      Logger.new($stdout)
    end

    def detect_root(app)
      return Rails.root.to_s if defined?(Rails) && Rails.respond_to?(:root) && Rails.root
      return unless app.respond_to?(:root) && app.root

      app.root.to_s
    end

    def detect_cleaner
      Rails.backtrace_cleaner if defined?(Rails) && Rails.respond_to?(:backtrace_cleaner)
    end

    def detect_format
      configured = ENV.fetch("CONCISE_ERRORS_FORMAT", nil)&.strip
      return configured.downcase.to_sym if configured && %w[text html].include?(configured.downcase)

      :html
    end

    def disable_web_console(stack)
      return unless defined?(WebConsole::Middleware)

      stack.delete(WebConsole::Middleware)
    end

    def swap_show_exceptions(stack)
      # Ensure ActionDispatch::ShowExceptions exists before trying to swap
      stack.use ::ActionDispatch::ShowExceptions

      begin
        stack.swap ::ActionDispatch::ShowExceptions, ConciseErrors::ShowExceptions
        stack.delete ::ActionDispatch::ShowExceptions
      rescue RuntimeError
        stack.delete ::ActionDispatch::ShowExceptions
        stack.use ConciseErrors::ShowExceptions
      end
    end
  end
end
