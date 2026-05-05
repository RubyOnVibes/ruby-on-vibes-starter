require_relative "boot"
require "rails/all"

# Require the gems listed in Gemfile, including any gems
# you've limited to :test, :development, or :production.
Bundler.require(*Rails.groups)

require "async/cable"

# Eagerly load RubyOnVibes config before Rails application initialization
# so it's available in environment configs (development.rb, production.rb, etc.)
require_relative "../lib/ruby_on_vibes"

# Vendored: concise error pages for development and mounted vibes mode
require_relative "../lib/concise_errors"

module RubyOnVibesTemplate
  class Application < Rails::Application
    # Initialize configuration defaults for originally generated Rails version.
    config.load_defaults 8.0

    config.active_record.permanent_connection_checkout = :disallowed
    # Config Falcon (DB) isolation https://www.youtube.com/watch?v=8-o1XR070g0&t=414s
    config.active_support.isolation_level = :fiber

    # Please, add to the `ignore` list any other `lib` subdirectories that do
    # not contain `.rb` files, or that should not be reloaded or eager loaded.
    # Common ones are `templates`, `generators`, or `middleware`, for example.
    config.autoload_lib(ignore: %w[assets tasks engines ruby_on_vibes.rb ruby_on_vibes concise_errors.rb concise_errors payments])

    # Configuration for the application, engines, and railties goes here.
    #
    # These settings can be overridden in specific environments using the files
    # in config/environments, which are processed later.
    #
    # config.time_zone = "Central Time (US & Canada)"
    # config.eager_load_paths << Rails.root.join("extras")

    # Autoload custom validators from app/validators
    config.autoload_paths << Rails.root.join("app/validators")

    # Autoload context classes from app/models/contexts
    # (e.g. WorkspaceContext, not Contexts::WorkspaceContext)
    config.autoload_paths << Rails.root.join("app/models/contexts")
    config.eager_load_paths << Rails.root.join("app/models/contexts")

    # Replace the default in-process memory cache store with a durable alternative.
    config.cache_store = :solid_cache_store
    # Use solid_queue for the default background jobs queue adapter
    config.active_job.queue_adapter = :solid_queue
    # Connect to the queue database
    config.solid_queue.connects_to = { database: { writing: :queue } }
  end
end
