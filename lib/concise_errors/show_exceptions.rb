# frozen_string_literal: true

require "action_dispatch/middleware/show_exceptions"
require "action_dispatch/middleware/debug_exceptions"

module ConciseErrors
  # Replacement middleware for production that renders concise error pages instead of generic 500 pages.
  class ShowExceptions < ::ActionDispatch::ShowExceptions
    def initialize(app, exceptions_app = nil)
      @original_exceptions_app = exceptions_app
      @app = app
      super(app, exceptions_app || method(:render_concise_exception))
    end

    def call(env)
      request = ActionDispatch::Request.new(env)
      
      # If full error page is requested, use DebugExceptions to render it
      if full_error_requested?(request)
        return debug_exceptions_middleware.call(env)
      end

      super
    end

    private

    def render_concise_exception(env)
      request = ActionDispatch::Request.new(env)
      wrapper = build_wrapper(env)

      formatter = Formatter.new(wrapper, request, ConciseErrors.configuration)
      
      [
        wrapper.status_code,
        { "Content-Type" => formatter.content_type },
        [formatter.body]
      ]
    end

    def build_wrapper(env)
      exception = env["action_dispatch.exception"]
      backtrace_cleaner = env["action_dispatch.backtrace_cleaner"] || ConciseErrors.configuration.cleaner
      
      # Ensure we have backtrace cleaner
      unless backtrace_cleaner
        backtrace_cleaner = if defined?(Rails) && Rails.respond_to?(:backtrace_cleaner)
                              Rails.backtrace_cleaner
                            else
                              nil
                            end
      end
      
      ActionDispatch::ExceptionWrapper.new(backtrace_cleaner, exception)
    end

    def full_error_requested?(request)
      flag = ConciseErrors.configuration.full_error_param
      return false if flag.nil? || flag.to_s.empty?

      request.query_parameters.key?(flag.to_s)
    end

    def debug_exceptions_middleware
      # Use Rails' DebugExceptions to show the full error page
      @debug_exceptions_middleware ||= begin
        debug_ex = ::ActionDispatch::DebugExceptions.new(@app)
        
        # If WebConsole is available, wrap it
        if defined?(WebConsole::Middleware)
          WebConsole::Middleware.new(debug_ex)
        else
          debug_ex
        end
      end
    end
  end
end

