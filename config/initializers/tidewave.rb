# frozen_string_literal: true

# Tidewave MCP Server for Ruby on Vibes
# Provides backend introspection tools for the platform via Model Context Protocol
#
if ENV['TIDEWAVE_ENABLED'] == 'true'  
  if ENV['TIDEWAVE_SHARED_SECRET'].present?
    Rails.application.config.tidewave.tap do |config|      
      # Authentication (required in production)
      config.shared_secret = ENV.fetch('TIDEWAVE_SHARED_SECRET')
      
      # Tool access mode
      config.mode = ENV.fetch('TIDEWAVE_MODE', 'readonly').to_sym
      
      # Allow remote access (we validate via bearer token)
      config.allow_remote_access = true   
      
      # Logging
      config.logger = Logger.new(Rails.root.join('log', 'tidewave.log'))

      if ENV['USE_MOUNTED_VIBES'] == 'true'
        # Configure path to persistent volume for Docker deployments
        config.production_log_file = '/mnt/data/code/log/production.log'

        # Always log exceptions (critical for debugging)
        config.async_job_log_exceptions = true
        
        # Optionally log all runs (verbose, good for performance analysis)
        config.async_job_log_runs = ENV['LOG_SUCCESSFUL_JOBS'] == 'true'
        
        # Configure paths to persistent volume
        config.async_job_exceptions_file = '/mnt/data/code/log/async_job_exceptions.log'
        config.async_job_runs_file = '/mnt/data/code/log/async_job_runs.log'
        
        # Optional: Customize rotation settings
        # config.async_job_exceptions_max_size = 10.megabytes
        # config.async_job_exceptions_rotations = 3
      end
      
      # Rails.logger.info "[Tidewave] MCP server enabled in #{config.mode} mode"
    end
  else
    Rails.logger.warn "[Tidewave] TIDEWAVE_ENABLED=true but no TIDEWAVE_SHARED_SECRET, disabling MCP"
    Rails.application.config.tidewave.enabled = false
  end
elsif ENV['USE_MOUNTED_VIBES'] == 'true'
  # Mounted in Ruby on Vibes but MCP disabled (user did not opt-in)
  # This is the default secure configuration
  Rails.logger.info "[Tidewave] MCP disabled (set TIDEWAVE_ENABLED=true to enable backend introspection)"
elsif Rails.env.development?
  # Local dev - MCP auto-enabled for convenience
  Rails.application.config.tidewave.tap do |config|
    config.allow_remote_access = true
    config.logger = Logger.new(Rails.root.join('log', 'tidewave.log'))
    Rails.logger.info "[Tidewave] MCP auto-enabled in development"
  end
else
  # Running without Ruby on Vibes - MCP disabled
  Rails.logger.debug "[Tidewave] MCP disabled"
  Rails.application.config.tidewave.enabled = false
end
