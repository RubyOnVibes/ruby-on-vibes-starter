# frozen_string_literal: true

require "net/http"
require "uri"
require "ipaddr"
require "socket"

class WebFetchTool < RubyLLM::Tool
  description <<~DESC
    Fetches a web page and returns its text content.

    WHEN TO USE THIS:
    - When the user pastes a URL and wants you to read or summarize it
    - When you need to reference documentation, articles, or other web content
    - When the user asks about content at a specific URL

    HOW IT WORKS:
    - Fetches the page, strips HTML tags, scripts, styles, and navigation chrome
    - Returns clean readable text, truncated to avoid excessive token usage
    - Follows redirects (up to 5)

    LIMITATIONS:
    - Cannot access pages behind authentication or paywalls
    - JavaScript-rendered content (SPAs) may not be fully available
    - Very large pages are truncated to keep responses manageable
  DESC

  params do
    string :url, description: "The URL to fetch (must start with http:// or https://)", required: true
  end

  MAX_CONTENT_LENGTH = 40_000  # characters — roughly 10K tokens
  MAX_RESPONSE_BYTES = 5_000_000  # 5MB max download
  MAX_REDIRECTS = 5
  REQUEST_TIMEOUT = 15 # seconds

  # Block requests to private/internal networks (SSRF protection)
  BLOCKED_IP_RANGES = [
    IPAddr.new("10.0.0.0/8"),
    IPAddr.new("172.16.0.0/12"),
    IPAddr.new("192.168.0.0/16"),
    IPAddr.new("127.0.0.0/8"),
    IPAddr.new("169.254.0.0/16"),
    IPAddr.new("0.0.0.0/8"),
    IPAddr.new("::1/128"),
    IPAddr.new("fc00::/7"),
    IPAddr.new("fe80::/10")
  ].freeze

  attr_reader :chat, :sender_user, :sender_member, :sender_workspace

  def initialize(chat:, sender_user: nil, sender_member: nil, sender_workspace: nil)
    @chat = chat
    @sender_user = sender_user
    @sender_member = sender_member
    @sender_workspace = sender_workspace
  end

  def execute(url:)
    url = url.strip
    unless url.match?(%r{\Ahttps?://}i)
      return { error: "Invalid URL: must start with http:// or https://" }
    end

    uri = URI.parse(url)
    unless uri.is_a?(URI::HTTP) || uri.is_a?(URI::HTTPS)
      return { error: "Invalid URL format" }
    end

    response_body, content_type = fetch_with_redirects(uri)
    text = if html_content?(content_type)
      extract_text(response_body)
    else
      # Plain text, JSON, etc. — return as-is
      response_body.encode("UTF-8", invalid: :replace, undef: :replace, replace: "")
    end

    if text.blank?
      return "(No readable content found at #{url})"
    end

    truncated = text.length > MAX_CONTENT_LENGTH
    text = text[0...MAX_CONTENT_LENGTH] if truncated

    # Return plain string — avoids Hash#to_s escaping newlines as literal \n
    if truncated
      "Content from #{url} (truncated to #{MAX_CONTENT_LENGTH} chars):\n\n#{text}"
    else
      "Content from #{url}:\n\n#{text}"
    end
  rescue URI::InvalidURIError
    { error: "Invalid URL format: #{url}" }
  rescue Net::OpenTimeout, Net::ReadTimeout
    { error: "Request timed out after #{REQUEST_TIMEOUT}s" }
  rescue SocketError => e
    { error: "Could not connect: #{e.message}" }
  rescue => e
    { error: "Failed to fetch URL: #{e.message}" }
  end

  private

  def fetch_with_redirects(uri, limit = MAX_REDIRECTS)
    raise "Too many redirects" if limit == 0
    validate_not_private!(uri)

    http = Net::HTTP.new(uri.host, uri.port)
    http.use_ssl = (uri.scheme == "https")
    http.open_timeout = REQUEST_TIMEOUT
    http.read_timeout = REQUEST_TIMEOUT

    request = Net::HTTP::Get.new(uri.request_uri)
    request["User-Agent"] = "Mozilla/5.0 (compatible; RubyOnVibes/1.0)"
    request["Accept"] = "text/html, application/xhtml+xml, text/plain"

    response = http.request(request)

    case response
    when Net::HTTPSuccess
      body = response.body
      raise "Response too large (#{body.bytesize} bytes)" if body.bytesize > MAX_RESPONSE_BYTES
      [body, response["content-type"].to_s]
    when Net::HTTPRedirection
      location = response["location"]
      new_uri = URI.parse(location)
      new_uri = URI.join(uri, location) unless new_uri.host
      fetch_with_redirects(new_uri, limit - 1)
    else
      raise "HTTP #{response.code}: #{response.message}"
    end
  end

  def validate_not_private!(uri)
    addrs = Socket.getaddrinfo(uri.host, nil, nil, :STREAM).map { |a| a[3] }.uniq
    addrs.each do |addr|
      ip = IPAddr.new(addr)
      if BLOCKED_IP_RANGES.any? { |range| range.include?(ip) }
        raise "Requests to private/internal networks are not allowed"
      end
    end
  rescue SocketError
    raise "Could not resolve hostname: #{uri.host}"
  end

  def html_content?(content_type)
    content_type.include?("text/html") || content_type.include?("application/xhtml")
  end

  def extract_text(html)
    doc = Nokogiri::HTML(html)

    # Remove elements that don't contribute readable content
    doc.css("script, style, noscript, iframe, svg, nav, footer, header").remove

    target = doc.at_css("body")
    return "" unless target

    # Get text and clean up noise
    text = target.text
    text = text.gsub(/\\[nrt]/, " ")      # literal \n \r \t escape sequences
    text = text.gsub(/\\u[0-9a-fA-F]{4}/, "")  # literal unicode escapes like \u00a0
    text = text.gsub(/[\u200B\u200C\u200D\uFEFF]/, "") # zero-width chars
    text = text.gsub(/[ \t]+/, " ")       # collapse horizontal whitespace
    text = text.gsub(/\n{3,}/, "\n\n")    # collapse excessive newlines
    text.strip
  end
end
