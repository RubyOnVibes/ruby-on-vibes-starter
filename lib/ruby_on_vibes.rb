module RubyOnVibes
  autoload :Configuration, "ruby_on_vibes/configuration"

  def self.config
    @config ||= Configuration.new
  end

  def self.config=(value)
    @config = value
  end

  # Hot reload configuration from vibes.yml
  # Called by /vibes/api/reload endpoint to pick up config changes without restart
  # Thread-safe: Uses mutex to prevent concurrent reload attempts
  def self.reload!
    config_mutex.synchronize do
      @config = nil  # Clear memoization
      @config = Configuration.new  # Force fresh load from YAML
      
      # Sync all cached configs in gems/frameworks that don't read dynamically
      sync_all_dependent_configs!
      
      Rails.logger.info "✅ RubyOnVibes configuration reloaded from vibes.yml"
    end
    true
  rescue => e
    Rails.logger.error "❌ Failed to reload RubyOnVibes config: #{e.message}"
    false
  end
  
  private
  
  # Lazy-initialized mutex for thread-safe config reloading

  # Lazy-initialized mutex — one per process (works with Falcon's fiber model too)
  def self.config_mutex
    @config_mutex ||= Mutex.new
  end
  
  public
  
  # ========================================
  # DEPENDENT CONFIG SYNC (Single Source of Truth)
  # ========================================
  # These methods sync RubyOnVibes config to gems/frameworks that cache values at boot.
  # Each initializer calls its specific sync method, and hot reload calls sync_all.
  
  # Sync Pay gem configuration
  # Called from: config/initializers/pay.rb and during hot reload
  #
  def self.sync_pay_config!
    return unless defined?(Pay)
    
    Pay.business_name = business_name
    Pay.business_address = business_address
    Pay.application_name = application_name
    Pay.support_email = support_email
  rescue => e
    Rails.logger.debug "Pay config sync failed: #{e.message}"
  end
  
  # Sync ActionMailer configuration for production
  # Called from: config/environments/production.rb (at boot) and during hot reload
  def self.sync_action_mailer_config!
    return unless defined?(Rails) && Rails.application.config.respond_to?(:action_mailer)
    
    # Set both host and protocol (production uses HTTPS)
    Rails.application.config.action_mailer.default_url_options = {
      host: mailer_host,
      protocol: "https"
    }
  rescue => e
    Rails.logger.debug "ActionMailer config sync failed: #{e.message}"
  end
  
  # Sync ActionMailer configuration for test environment
  # Called from: config/environments/test.rb (at boot)
  def self.sync_action_mailer_config_test!
    return unless defined?(Rails) && Rails.application.config.respond_to?(:action_mailer)
    
    # Test environment uses HTTP only
    Rails.application.config.action_mailer.default_url_options = {
      host: mailer_host
    }
  rescue => e
    Rails.logger.debug "ActionMailer test config sync failed: #{e.message}"
  end
  
  # Sync all dependent configs (called during hot reload in production)
  def self.sync_all_dependent_configs!
    sync_pay_config!
    sync_action_mailer_config!  # Production only - test env not running hot reload
  end

  # Convenience methods for accessing config values
  def self.application_name
    config.application_name
  end

  def self.business_name
    config.business_name
  end

  def self.business_address
    config.business_address
  end

  def self.support_email
    config.support_email
  end

  def self.support_phone
    config.support_phone
  end

  def self.mailer_host
    config.mailer_host
  end

  def self.default_from_email
    config.default_from_email
  end

  def self.payment_processors
    config.payment_processors
  end

  def self.stripe?
    config.stripe?
  end

  def self.teams
    config.teams
  end

  def self.teams?
    config.teams?
  end

  def self.show_workspaces?
    config.show_workspaces?
  end

  def self.referrals
    config.referrals
  end

  def self.referrals?
    config.referrals?
  end

  def self.dashboard?
    config.dashboard?
  end

  # True when RubyLLM is enabled
  def self.llm?
    return true if ENV['LLMS_ENABLED'] == 'true' # allows dev env override for rapid template iteration
    
    proxy_enabled = true # Ada, Claude (agents) etc. — LLM features enabled by default via platform proxy — change to false to disable for apps with no AI component.
    proxied = proxy_enabled && ENV["USE_MOUNTED_VIBES"] == "true" && ENV["VIBES_AI_PROXY_URL"].present?

    return true if proxied

    # fallback to local keys if proxy is not enabled
    anthropic_key = RubyLLM.config.anthropic_api_key
    openai_key    = RubyLLM.config.openai_api_key
    
    anthropic_key.present? || openai_key.present?
  end
  
  # llm?, chat?, and agent_tasks? can be overridden independently of each other.
  # e.g., disable chat but keep agent_tasks for cron-driven agents without chat UI.

  def self.chat?
    llm?
  end

  def self.agent_tasks?
    chat?
  end

  def self.agents?
    return true if ENV['AGENTS_ENABLED'] == 'true' # dev override for rapid template iteration

    agents_enabled = true # Persistent agents (Manager, webhooks, scheduled runs) — change to false for apps with no agent component.
    agents_enabled && agent_tasks?
  end

  # Debug/demo tools (echo task, failing task) for verifying the agent task pipeline.
  # Enabled in dev/test by default. Set VIBES_DEBUG_TOOLS=true in production to enable.
  def self.debug_tools?
    Rails.env.development? || Rails.env.test? || ENV["VIBES_DEBUG_TOOLS"].present?
  end

  # Email provider detection helpers
  # These determine which email system to default to based on environment configuration
  
  # Resend (production email provider) is enabled when API key is configured
  # Used for: sending real transactional emails to users.
  # Use this in production after verifying your domain on resend.com.
  def self.resend?
    ENV['RESEND_API_KEY'].present?
  end

  # Mailbin (dev/staging email capture) is enabled when:
  # 1. Running on with mounted Vibes (USE_MOUNTED_VIBES=true)
  # 2. Resend is NOT configured (no API key)
  # Used for: capturing emails locally or in staging environments for testing without sending real emails
  def self.mailbin?
    ENV['USE_MOUNTED_VIBES'] == 'true' && !resend?
  end
end