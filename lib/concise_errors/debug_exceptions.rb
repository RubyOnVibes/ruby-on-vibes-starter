# frozen_string_literal: true

require "action_dispatch/http/content_security_policy"
require "action_dispatch/http/mime_type"
require "action_dispatch/http/parameters"
require "action_dispatch/http/request"
require "action_dispatch/middleware/debug_exceptions"

module ConciseErrors
  # Replacement middleware that keeps the existing API while producing concise output.
  class DebugExceptions < ::ActionDispatch::DebugExceptions
    def call(env)
      request = ActionDispatch::Request.new(env)

      return fallback_web_console.call(env) if web_console_request?(request)

      return fallback_web_console.call(env) if full_error_requested?(request)

      env["action_dispatch.backtrace_cleaner"] ||= ConciseErrors.configuration.cleaner
      super
    end

    private

    def render_for_browser_request(request, wrapper)
      formatter = Formatter.new(wrapper, request, ConciseErrors.configuration)
      render(wrapper.status_code, formatter.body, formatter.content_type)
    end

    def logger(request)
      ConciseErrors.logger || super
    end

    def full_error_requested?(request)
      flag = ConciseErrors.configuration.full_error_param
      return false if flag.nil? || flag.to_s.empty?

      request.query_parameters.key?(flag.to_s)
    end

    def web_console_request?(request)
      return false unless defined?(WebConsole::Middleware)

      mount_point = WebConsole::Middleware.mount_point
      return false if mount_point.nil? || mount_point.empty?

      request.path.start_with?(mount_point)
    end

    def fallback_debug_exceptions
      @fallback_debug_exceptions ||= ::ActionDispatch::DebugExceptions.new(@app)
    end

    def fallback_web_console
      return fallback_debug_exceptions unless defined?(WebConsole::Middleware)

      @fallback_web_console ||= WebConsole::Middleware.new(fallback_debug_exceptions)
    end
  end
end
