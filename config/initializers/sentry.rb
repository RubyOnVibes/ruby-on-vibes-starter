if ENV['SENTRY_DSN'].present?
  require "sentry-ruby"

  Sentry.init do |config|
    config.dsn = ENV['SENTRY_DSN']
  end
end