# frozen_string_literal: true

# Rack::Attack: Rate limiting and throttling for MCP endpoints
#
# Protects your app from abuse if MCP token is compromised
# Configurable per-app via environment variables

# Only enable if explicitly enabled (user can disable if they want)
# Default ON for protection, but respects user choice
if ENV['USE_MOUNTED_VIBES'] == 'true' && 
   ENV['TIDEWAVE_ENABLED'] == 'true' &&
   ENV['MCP_RATE_LIMITING_ENABLED'] != 'false'  # Enabled by default, can opt-out
  
  # Generous defaults (customers pay for their own instance)
  # These limits prevent obvious abuse without restricting normal use
  MCP_RATE_LIMIT_PER_MINUTE = ENV.fetch('MCP_RATE_LIMIT_PER_MINUTE', '300').to_i  # 300/min = 5/sec
  MCP_RATE_LIMIT_PER_HOUR = ENV.fetch('MCP_RATE_LIMIT_PER_HOUR', '10000').to_i   # ~2.7/sec sustained
  
  # Normal debugging: ~20 requests in 5 minutes
  # Heavy usage: ~100-200 requests/hour
  # These defaults allow 50-100x normal usage before throttling
  
  Rack::Attack.throttle('mcp/ip', limit: MCP_RATE_LIMIT_PER_MINUTE, period: 1.minute) do |req|
    # Throttle by IP for all MCP/shell endpoints
    req.ip if req.path.start_with?('/tidewave')
  end
  
  Rack::Attack.throttle('mcp/token', limit: MCP_RATE_LIMIT_PER_HOUR, period: 1.hour) do |req|
    # Throttle by bearer token (more important than IP)
    if req.path.start_with?('/tidewave')
      # Extract bearer token from Authorization header
      auth_header = req.env['HTTP_AUTHORIZATION']
      if auth_header && auth_header.start_with?('Bearer ')
        auth_header.sub(/^Bearer /, '')
      end
    end
  end
  
  # Log rate limit events (helps detect attacks)
  ActiveSupport::Notifications.subscribe('rack.attack') do |name, start, finish, request_id, payload|
    req = payload[:request]
    
    if req.env['rack.attack.matched']
      discriminator = req.env['rack.attack.match_discriminator']
      matched_name = req.env['rack.attack.matched']
      
      Rails.logger.warn "[RackAttack] Rate limit hit: #{matched_name} for #{discriminator} - #{req.path}"
      
      # Could notify platform here if you want alerts
      # HTTP.post("#{ENV['PLATFORM_URL']}/api/rate_limit_alerts", {
      #   app_id: ENV['APP_ID'],
      #   discriminator: discriminator,
      #   path: req.path
      # })
    end
  end
  
  # Customize throttled response
  Rack::Attack.throttled_responder = lambda do |env|
    match_data = env['rack.attack.match_data']
    now = match_data[:epoch_time]
    
    headers = {
      'Content-Type' => 'application/json',
      'RateLimit-Limit' => match_data[:limit].to_s,
      'RateLimit-Remaining' => '0',
      'RateLimit-Reset' => (now + (match_data[:period] - now % match_data[:period])).to_s
    }
    
    body = {
      error: 'Rate limit exceeded',
      message: 'Too many requests. Please try again later.',
      retry_after: match_data[:period] - now % match_data[:period]
    }
    
    [429, headers, [JSON.generate(body)]]
  end
  
  Rails.logger.info "[RackAttack] MCP rate limiting enabled: #{MCP_RATE_LIMIT_PER_MINUTE}/min, #{MCP_RATE_LIMIT_PER_HOUR}/hour"
end
