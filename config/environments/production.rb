require "active_support/core_ext/integer/time"

Rails.application.configure do
  # Settings specified here will take precedence over those in config/application.rb.

  # Code is not reloaded between requests.
  config.enable_reloading = false

  # Eager load code on boot for better performance and memory savings (ignored by Rake tasks).
  config.eager_load = true

  # Full error reports are disabled.
  config.consider_all_requests_local = false

  # Turn on fragment caching in view templates.
  config.action_controller.perform_caching = true

  # Cache assets for far-future expiry since they are all digest stamped.
  config.public_file_server.headers = { "cache-control" => "public, max-age=#{1.year.to_i}" }

  # Enable serving of images, stylesheets, and JavaScripts from an asset server.
  # config.asset_host = "http://assets.example.com"

  # Store uploaded files on the local file system (see config/storage.yml for options).
  config.active_storage.service = :local

  # Assume all access to the app is happening through a SSL-terminating reverse proxy.
  config.assume_ssl = true

  # Force all access to the app over SSL, use Strict-Transport-Security, and use secure cookies.
  config.force_ssl = true

  # Skip http-to-https redirect for the default health check endpoint.
  # config.ssl_options = { redirect: { exclude: ->(request) { request.path == "/up" } } }

  # Log to STDOUT with the current request id as a default log tag.
  config.log_tags = [ :request_id ]
  # CONDITIONAL: dual_logger.rb initializer handles logger setup for vibecoding (STDOUT + file for MCP)
  # For vanilla Rails deploys, use standard STDOUT logging:
  config.logger = ActiveSupport::TaggedLogging.logger(STDOUT) unless ENV['USE_MOUNTED_VIBES'] == 'true'

  # Change to "debug" to log everything (including potentially personally-identifiable information!)
  config.log_level = ENV.fetch("RAILS_LOG_LEVEL", "info")

  # Prevent health checks from clogging up the logs.
  config.silence_healthcheck_path = "/up"

  # Don't log any deprecations.
  config.active_support.report_deprecations = false

  # Ignore bad email addresses and do not raise email delivery errors.
  # Set this to true and configure the email server for immediate delivery to raise delivery errors.
  # config.action_mailer.raise_delivery_errors = false

  # Set host to be used by links generated in mailer templates.
  RubyOnVibes.sync_action_mailer_config!

  # Configure default URL options for background jobs and routes helpers, etc
  Rails.application.routes.default_url_options = { host: ENV.fetch('APPLICATION_URL', 'localhost:3000'), protocol: 'https' }

  # Email delivery configuration (priority: Resend → Mailbin → disabled)
  if RubyOnVibes.resend?
    # Production email delivery via Resend
    # Requires verified domain on resend.com and API key in ENV['RESEND_API_KEY']
    config.action_mailer.delivery_method = :resend
    config.action_mailer.resend_settings = {
      api_key: ENV.fetch('RESEND_API_KEY')
    }
  elsif RubyOnVibes.mailbin?
    # Development email capture (for testing without external provider)
    # Stores emails on persistent Fly volume for debugging
    config.action_mailer.delivery_method = :mailbin
    config.action_mailer.perform_deliveries = true
    # Emails stored at /mnt/data/mailbin/*.eml (viewable at /admin/mailbin by admins)
  else
    # No email provider configured - disable delivery to surface issues early
    config.action_mailer.perform_deliveries = false
    config.action_mailer.raise_delivery_errors = true
  end

  # config.action_mailer.mailgun_settings = {
  #   api_key: ENV.fetch('MAILGUN_API_KEY', ''),
  #   domain: "mail.#{RubyOnVibes.mailer_host}",
  #   # timeout: 20 # Default depends on rest-client, whose default is 60s. Added in 1.2.3.
  # }

  # Specify outgoing SMTP server. Remember to add smtp/* credentials via rails credentials:edit.
  # config.action_mailer.smtp_settings = {
  #   user_name: Rails.application.credentials.dig(:smtp, :user_name),
  #   password: Rails.application.credentials.dig(:smtp, :password),
  #   address: "smtp.example.com",
  #   port: 587,
  #   authentication: :plain
  # }

  # Enable locale fallbacks for I18n (makes lookups for any locale fall back to
  # the I18n.default_locale when a translation cannot be found).
  config.i18n.fallbacks = true

  # Do not dump schema after migrations.
  config.active_record.dump_schema_after_migration = false

  # Only use :id for inspections in production.
  config.active_record.attributes_for_inspect = [ :id ]

  # Enable concise errors in production for mounted Vibes engine.
  config.concise_errors.enable_in_production = (ENV['USE_MOUNTED_VIBES'] == 'true')

  # Enable DNS rebinding protection and other `Host` header attacks.
  # config.hosts = [
  #   "example.com",     # Allow requests from example.com
  #   /.*\.example\.com/ # Allow requests from subdomains like `www.example.com`
  # ]
  #
  # Skip DNS rebinding protection for the default health check endpoint.
  # config.host_authorization = { exclude: ->(request) { request.path == "/up" } }
end

# Optional hot-reload behavior for mounted Vibes engine in production when explicitly enabled.
if ENV['USE_MOUNTED_VIBES'] == 'true'
  Rails.application.configure do
    config.enable_reloading = true
    config.action_controller.perform_caching = false
    # Ensure templates are not cached between requests
    if config.respond_to?(:action_view)
      config.action_view.cache_template_loading = false
    end
  end
end
