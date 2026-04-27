# Dual Logger for Vibecoding (STDOUT and File)
#
# ONLY enabled when USE_MOUNTED_VIBES=true (Fly vibecoding platform)
# For vanilla Rails deploys (Render, Kamal), use standard STDOUT logging
#
# Rails 8 defaults to STDOUT logging (for Fly log aggregation).
# BUT MCP (Model Context Protocol) needs a file to read from.
#
# Solution for vibecoding - log to BOTH destinations
#   - STDOUT for Fly log aggregator, `fly logs`
#   - File for MCP tool (get_logs) backend console access
#
# Log file location:
#   - Mounted mode: /mnt/data/code/log/production.log (persisted to volume)
#   - Image mode: /rails/log/production.log (ephemeral, but ok for MCP queries)
#
# Disk usage (20GB volume shared with SQLite, gems, code, mailbin):
#   - Max log size: 100MB (10 files × 10MB each = 0.5% of volume)
#   - Provides 12+ hours of logs for medium traffic apps
#   - Rotation prevents disk bloat while keeping AI debugging context

if Rails.env.production? && ENV['USE_MOUNTED_VIBES'] == 'true'
  require 'logger'
  
  # Determine log file path based on mounted vs image mode
  log_file_path = if ENV['USE_MOUNTED_VIBES'] == 'true' && Dir.exist?('/mnt/data/code')
    '/mnt/data/code/log/production.log'
  else
    Rails.root.join('log', 'production.log')
  end
  
  # Ensure log directory exists (docker-entrypoint creates it, but be defensive)
  FileUtils.mkdir_p(File.dirname(log_file_path))
  
  # Create file logger with rotation balanced for AI debugging + disk space
  # Keep 9 old files: production.log, .0-.8 = 10 files × 10MB = 100MB max
  # Volume breakdown (20GB total):
  #   - Logs: 100MB (0.5%)
  #   - SQLite: ~500MB
  #   - Gems: ~300MB
  #   - Code: ~100MB
  #   - Mailbin: ~100MB
  #   - Free: ~19GB
  # Coverage:
  #   - Low traffic (10 req/min): ~5 days of logs
  #   - Medium traffic (100 req/min): ~12 hours of logs
  #   - High traffic (1000 req/min): ~1 hour of logs
  file_logger = Logger.new(log_file_path, 
    9,          # Keep 9 old files (10 files total)
    10.megabytes # Rotate at 10MB each
  )
  file_logger.formatter = Logger::Formatter.new
  file_logger.level = Logger::INFO
  
  # Create STDOUT logger (existing behavior)
  stdout_logger = Logger.new(STDOUT)
  stdout_logger.formatter = Logger::Formatter.new
  stdout_logger.level = Logger::INFO
  
  # Combine loggers using ActiveSupport::BroadcastLogger
  broadcast_logger = ActiveSupport::BroadcastLogger.new(stdout_logger, file_logger)
  
  # Wrap with tagged logging (preserves request_id tags)
  new_logger = ActiveSupport::TaggedLogging.new(broadcast_logger)
  Rails.application.config.logger = new_logger
  
  # CRITICAL: Test write to confirm everything works
  # This appears in both STDOUT (fly logs) and file (MCP get_logs)
  new_logger.info "✅ [Boot] Dual logger initialized: STDOUT + #{log_file_path}"
  new_logger.info "✅ [Boot] Log file exists: #{File.exist?(log_file_path)}"
  new_logger.info "✅ [Boot] Log file writable: #{File.writable?(log_file_path)}"
  new_logger.info "✅ [Boot] Tidewave enabled: #{ENV['TIDEWAVE_ENABLED'] || 'false'}"
  new_logger.info "✅ [Boot] USE_MOUNTED_VIBES: #{ENV['USE_MOUNTED_VIBES'] || 'false'}"
  
  # Force flush to ensure test message is written
  file_logger.flush if file_logger.respond_to?(:flush)
end

