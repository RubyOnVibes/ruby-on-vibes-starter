# frozen_string_literal: true

require "erb"
require "json"
require "rack/utils"

module ConciseErrors
  # Builds the compact error payload for browser responses.
  class Formatter
    OMITTED_SUFFIX = "... %<count>d more lines omitted"

    def initialize(wrapper, request, configuration)
      @wrapper = wrapper
      @request = request
      @configuration = configuration
    end

    def body
      response_format == :html ? html_payload : text_payload
    end

    def content_type
      response_format == :html ? "text/html" : "text/plain"
    end

    private

    attr_reader :wrapper, :request, :configuration

    def response_format
      return :text if prefers_plain_text?

      configuration.format
    end

    def text_payload
      [heading_line, status_line, "", *truncated_trace].compact.join("\n")
    end

    def html_payload
      <<~HTML
        <!DOCTYPE html>
        <html lang="en">
          <head>
            <meta charset="utf-8" />
            <meta name="viewport" content="width=device-width, initial-scale=1">
            <title>#{html_escape(heading_line)}</title>
            #{error_page_styles}
          </head>
          <body>
            <div class="container">
              <div class="error-header">
                <h1>#{html_escape(wrapper.exception_class_name)}</h1>
                <p class="error-message">#{html_escape(wrapper.message)}</p>
                <p class="status-line">#{html_escape(status_line)}</p>
              </div>
              
              #{code_context_section}
              
              <div class="trace-section">
                <h2>Stack Trace</h2>
                <pre class="trace">#{html_escape(formatted_trace)}</pre>
              </div>
              
              #{full_error_button_dev_only}
            </div>
          </body>
        </html>
      HTML
    end

    def heading_line
      "#{wrapper.exception_class_name}: #{wrapper.message}".strip
    end

    def status_line
      status = wrapper.status_code
      message = Rack::Utils::HTTP_STATUS_CODES[status] || "Internal Server Error"
      "HTTP #{status} (#{message})"
    end

    def truncated_trace
      full_trace = raw_trace.map { |line| sanitize_trace(line) }
      limit = configuration.stack_trace_lines

      return full_trace if limit.nil? || limit <= 0 || full_trace.size <= limit

      full_trace.first(limit) + [Kernel.format(OMITTED_SUFFIX, count: full_trace.size - limit)]
    end
    
    def raw_trace
      # Try multiple ways to get the trace
      trace = wrapper.exception_trace
      
      if trace.nil? || trace.empty?
        exception = wrapper.exception
        trace = exception&.backtrace || []
      end
      
      # Last resort: try application_trace
      if trace.empty? && wrapper.respond_to?(:application_trace)
        trace = wrapper.application_trace || []
      end
      
      Array(trace)
    end

    def html_escape(string)
      ERB::Util.html_escape(string)
    end

    def prefers_plain_text?
      return true if request.xhr?

      accept = request.get_header("HTTP_ACCEPT").to_s
      return false if accept.empty?

      !accept.downcase.include?("html")
    end

    def sanitize_trace(line)
      root = configuration.application_root.to_s
      return line if root.empty?

      line.sub(%r{\A#{Regexp.escape(root)}/?}, "./")
    end

    def formatted_trace
      trace = truncated_trace
      return "No stack trace available" if trace.empty?
      
      trace.map.with_index do |line, index|
        "#{index}: #{line}"
      end.join("\n")
    end

    def full_error_button_dev_only
      # Only show button in development (not production)
      return "" if production_mode?
      return "" unless flag_parameter

      flagged = flagged_url
      return "" unless flagged

      <<~HTML
        <button type="button" onclick="window.location.href='#{html_escape(flagged)}'">
          Show original error page
        </button>
      HTML
    end

    def production_mode?
      # Check if we're in production mode
      return true if configuration.enable_in_production?
      
      # Also check Rails.env if available
      if defined?(Rails) && Rails.respond_to?(:env)
        return Rails.env.production?
      end
      
      false
    end

    def flagged_url
      flag = flag_parameter
      return unless flag

      params = request.query_parameters.dup
      params[flag] = "1"

      query = Rack::Utils.build_nested_query(params)
      base_path = request.fullpath.split("?", 2).first
      return base_path if query.empty?

      "#{base_path}?#{query}"
    end

    def flag_parameter
      value = configuration.full_error_param
      return if value.nil?

      string = value.to_s.strip
      string.empty? ? nil : string
    end

    def code_context_section
      context = extract_code_context
      return "" unless context

      <<~HTML
        <div class="code-context">
          <h2>#{html_escape(context[:file])}:#{context[:line]}</h2>
          <pre class="code">#{render_code_lines(context)}</pre>
        </div>
      HTML
    end

    def extract_code_context
      trace_lines = raw_trace
      return nil if trace_lines.empty?

      first_line = trace_lines.first
      # Parse format like: "app/controllers/debug_controller.rb:5:in `test_error'"
      match = first_line.match(/^(.+?):(\d+)(?::in|$)/)
      return nil unless match

      file_path = match[1]
      line_number = match[2].to_i
      
      # Resolve relative path from application root
      root = configuration.application_root.to_s
      full_path = file_path.start_with?("/") ? file_path : File.join(root, file_path)
      
      return nil unless File.exist?(full_path)

      {
        file: file_path,
        line: line_number,
        full_path: full_path
      }
    rescue StandardError
      nil
    end

    def render_code_lines(context)
      lines = File.readlines(context[:full_path])
      target_line = context[:line]
      
      # Show 3 lines before and after
      start_line = [target_line - 3, 1].max
      end_line = [target_line + 3, lines.length].min
      
      (start_line..end_line).map do |line_num|
        line_content = lines[line_num - 1].chomp
        if line_num == target_line
          "<span class=\"error-line\">#{line_num}: #{html_escape(line_content)}</span>"
        else
          "#{line_num}: #{html_escape(line_content)}"
        end
      end.join("\n")
    rescue StandardError
      ""
    end

    def error_page_styles
      <<~CSS
        <style>
          * { margin: 0; padding: 0; box-sizing: border-box; }
          
          body {
            font-family: -apple-system, BlinkMacSystemFont, "Segoe UI", Roboto, "Helvetica Neue", Arial, sans-serif;
            line-height: 1.6;
            color: #333;
            background: #f8f9fa;
            padding: 20px;
          }
          
          .container {
            max-width: 1200px;
            margin: 0 auto;
            background: white;
            border-radius: 8px;
            box-shadow: 0 2px 10px rgba(0,0,0,0.1);
            overflow: hidden;
          }
          
          .error-header {
            background: linear-gradient(135deg, #dc3545 0%, #c82333 100%);
            color: white;
            padding: 30px;
            border-bottom: 4px solid #bd2130;
          }
          
          .error-header h1 {
            font-size: 28px;
            font-weight: 600;
            margin-bottom: 10px;
          }
          
          .error-message {
            font-size: 18px;
            margin-bottom: 10px;
            opacity: 0.95;
          }
          
          .status-line {
            font-size: 14px;
            opacity: 0.8;
            font-family: "SF Mono", Monaco, "Cascadia Code", "Roboto Mono", Consolas, "Courier New", monospace;
          }
          
          .code-context, .trace-section {
            padding: 30px;
          }
          
          .code-context {
            background: #f8f9fa;
            border-bottom: 1px solid #dee2e6;
          }
          
          h2 {
            font-size: 16px;
            font-weight: 600;
            margin-bottom: 15px;
            color: #495057;
            text-transform: uppercase;
            letter-spacing: 0.5px;
          }
          
          pre {
            background: #2d2d2d;
            color: #f8f8f2;
            padding: 20px;
            border-radius: 6px;
            overflow-x: auto;
            font-family: "SF Mono", Monaco, "Cascadia Code", "Roboto Mono", Consolas, "Courier New", monospace;
            font-size: 14px;
            line-height: 1.5;
          }
          
          pre.code {
            background: #1e1e1e;
            border-left: 4px solid #dc3545;
          }
          
          .error-line {
            background: #dc354520;
            display: block;
            margin: 0 -20px;
            padding: 0 20px;
            border-left: 4px solid #dc3545;
          }
          
          pre.trace {
            background: #2d2d2d;
            max-height: 400px;
            overflow-y: auto;
          }
          
          button {
            background: #007bff;
            color: white;
            border: none;
            padding: 12px 24px;
            font-size: 14px;
            font-weight: 500;
            border-radius: 6px;
            cursor: pointer;
            margin: 0 30px 30px 30px;
            transition: background 0.2s;
          }
          
          button:hover {
            background: #0056b3;
          }
          
          button:active {
            transform: translateY(1px);
          }
          
          @media (max-width: 768px) {
            body { padding: 10px; }
            .container { border-radius: 0; }
            .error-header, .code-context, .trace-section { padding: 20px; }
            pre { font-size: 12px; padding: 15px; }
          }
        </style>
      CSS
    end
  end
end
