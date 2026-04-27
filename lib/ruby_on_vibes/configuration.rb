module RubyOnVibes
  # Configuration class for app identity and business information
  # 
  # CRITICAL: This is the ONLY place app/business identity values should be read from
  # - Source of truth: config/vibes.yml
  # - Backend/ERB: Use RubyOnVibes.* methods (e.g., RubyOnVibes.application_name)
  # - Frontend JS/TS/JSX/TSX: Use window.App.data() (e.g., window.App.data().name)
  # 
  # Hot Reload: Changes to config/vibes.yml trigger engine reload, which re-initializes this class
  # All values have safe defaults - won't break if missing from config/vibes.yml
  class Configuration
    attr_accessor :application_name
    attr_accessor :business_name
    attr_accessor :business_address
    attr_accessor :support_email
    attr_accessor :support_phone
    attr_accessor :mailer_host
    attr_accessor :default_from_email
    attr_accessor :payment_processors
    attr_accessor :teams
    attr_accessor :referrals
    attr_accessor :dashboard

    def initialize
      load_from_yaml
      apply_defaults
    end

    def stripe?
      payment_processors&.include?("stripe")
    end

    def teams?
      teams || false
    end

    def show_workspaces?
      teams? # default to showing workspaces if only teams are enabled
    end

    def referrals?
      referrals || false
    end

    def dashboard?
      dashboard != false  # Default true, opt-out
    end

    private

    def load_from_yaml
      config_path = Rails.root.join("config", "vibes.yml")
      
      if File.exist?(config_path)
        yaml_config = YAML.load_file(config_path) || {}
        yaml_config.each do |key, value|
          send("#{key}=", value) if respond_to?("#{key}=") && value.present?
        end
      end
    end

    def apply_defaults
      @application_name ||= "My App"
      @business_name ||= "My Company, LLC"
      @business_address ||= ""
      @payment_processors ||= []
      @mailer_host ||= default_mailer_host
      @support_email ||= "support@#{@mailer_host}"
      @support_phone ||= ""
      @default_from_email ||= "no-reply@#{@mailer_host}"
    end

    def default_mailer_host
      if Rails.env.production?
        url = ENV['APPLICATION_URL']
        url ? URI.parse(url).host : "example.com"
      else
        "localhost"
      end
    rescue URI::InvalidURIError
      "example.com"
    end
  end
end

