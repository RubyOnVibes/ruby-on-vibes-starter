source "https://rubygems.org"

# Bundle edge Rails instead: gem "rails", github: "rails/rails", branch: "main"
gem "rails", "~> 8.1.0"
# The modern asset pipeline for Rails [https://github.com/rails/propshaft]
gem "propshaft"
# Use sqlite3 as the database for Active Record
gem "sqlite3", ">= 2.1"
# Use PostgreSQL as the database for Active Record (optional upgrade from SQLite)
gem "pg", "~> 1.6", ">= 1.6.2"
# Use the Falcon web server [https://github.com/socketry/falcon]
gem "falcon"
# Use JavaScript with ESM import maps [https://github.com/rails/importmap-rails]
gem "importmap-rails"
# Hotwire's SPA-like page accelerator [https://turbo.hotwired.dev]
gem "turbo-rails"
# Build JSON APIs with ease [https://github.com/rails/jbuilder]
gem "jbuilder"

# Use Active Model has_secure_password [https://guides.rubyonrails.org/active_model_basics.html#securepassword]
# gem "bcrypt", "~> 3.1.7"

# Windows does not include zoneinfo files, so bundle the tzinfo-data gem
gem "tzinfo-data", platforms: %i[ windows jruby ]

# Use the database-backed adapters for Rails.cache and Active Job
gem "solid_cache"
gem "solid_queue"

# Reduces boot times through caching; required in config/boot.rb
gem "bootsnap", require: false

# Rack middleware for rate limiting and request throttling
gem "rack-attack"

# Deploy this application anywhere as a Docker container [https://kamal-deploy.org]
gem "kamal", require: false

# Add HTTP asset caching/compression and X-Sendfile acceleration to Puma [https://github.com/basecamp/thruster/]
gem "thruster", require: false

# Use Active Storage variants [https://guides.rubyonrails.org/active_storage_overview.html#transforming-images]
# gem "image_processing", "~> 1.2"

group :development, :test do
  # https://github.com/rubysec/bundler-audit
  gem "bundler-audit", require: false

  # See https://guides.rubyonrails.org/debugging_rails_applications.html#debugging-with-the-debug-gem
  gem "debug", platforms: %i[ mri windows ], require: "debug/prelude"

  # Static analysis for security vulnerabilities [https://brakemanscanner.org/]
  gem "brakeman", require: false

  # Omakase Ruby styling [https://github.com/rails/rubocop-rails-omakase/]
  gem "rubocop-rails-omakase", require: false

  # https://github.com/rspec/rspec-rails
  gem "rspec-rails", "~> 8.0.0"
end

group :development do
  # Use console on exceptions pages [https://github.com/rails/web-console]
  gem "web-console"
end

group :test do
  # Use system testing [https://guides.rubyonrails.org/testing.html#system-testing]
  gem "capybara"
  gem "selenium-webdriver"
end

# https://github.com/aasm/aasm
# gem "aasm"

# https://github.com/ErwinM/acts_as_tenant
# gem "acts_as_tenant"

# https://github.com/socketry/async-cable
gem "async-cable"

# https://github.com/socketry/async-job-adapter-active_job
gem "async-job-adapter-active_job"

# https://github.com/ankane/ahoy_matey
# Optional — visit/event tracking; pairs with blazer for analytics dashboards.
gem "ahoy_matey"

# https://github.com/aws/aws-sdk-ruby
# gem 'aws-sdk-s3'

# https://github.com/ankane/blazer
# Optional — internal analytics dashboards; remove if you don't need them.
gem "blazer"

# https://github.com/bkeepers/dotenv
gem "dotenv", groups: [ :development, :test ]

# https://github.com/ankane/groupdate
# gem "groupdate"

# concise_errors - vendored in lib/concise_errors/ (no gem dependency needed)

# https://github.com/heartcombo/devise
gem "devise", "~> 5.0"

# https://github.com/inertiajs/inertia-rails
gem "inertia_rails"

# https://github.com/Praxis-Emergent/islandjs-rails
gem "islandjs-rails", "~> 2.0"

# https://github.com/janko/image_processing
gem "image_processing", "~> 1.2"

# https://github.com/excid3/madmin
# Optional — generated admin panel; remove if you'll build your own admin UI.
gem "madmin"

# https://github.com/rails/mission_control-jobs
gem "mission_control-jobs"

# https://github.com/excid3/mailbin
# Optional — captures emails in dev/preview when no SMTP/Resend is configured.
gem "mailbin"

# https://github.com/excid3/noticed
gem "noticed", "~> 2.8"

# https://github.com/ElMassimo/oj_serializers
# gem 'oj_serializers'

# https://github.com/pay-rails/pay
# Optional — billing/subscriptions. Pairs with stripe + receipts. Disable in config/vibes.yml.
gem "pay", "~> 11.6"

# https://github.com/ankane/pretender
gem "pretender"

# # https://github.com/omniauth/omniauth
# gem "omniauth", "~> 2.1"

# # https://github.com/cookpad/omniauth-rails_csrf_protection
# gem "omniauth-rails_csrf_protection", "~> 1.0"

# https://github.com/ddnexus/pagy
gem "pagy", "43.2.0"

# https://github.com/excid3/prefixed_ids
gem "prefixed_ids"

# https://github.com/varvet/pundit
gem "pundit"

# To use Receipts gem for creating invoice and receipt PDFs, also include:
gem "receipts", "~> 2.4"

# https://github.com/excid3/refer
gem "refer"

# https://github.com/resend/resend-ruby
gem "resend"

# https://github.com/crmne/ruby_llm
gem "ruby_llm", "1.13.2"

# https://github.com/getsentry/sentry-ruby
# gem "sentry-rails"

# https://github.com/stripe/stripe-ruby
gem "stripe", "~> 17.2"

# https://github.com/rails/tailwindcss-rails
gem "tailwindcss-rails"

# pin to tailwindcss version in package.json
gem "tailwindcss-ruby", "4.1.13"

# https://github.com/nativestranger/tidewave_rails
gem "tidewave", git: "https://github.com/nativestranger/tidewave_rails.git", branch: "vibes"

# https://github.com/ElMassimo/vite_rails
gem "vite_rails", "~> 3.0"
