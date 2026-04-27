class ApplicationMailer < ::ActionMailer::Base
  # Use lambda to evaluate from email dynamically on each send
  # This ensures hot reload of vibes.yml picks up new default_from_email
  default from: -> { RubyOnVibes.default_from_email }

  layout "mailer"
  
  helper VibesHelper
end