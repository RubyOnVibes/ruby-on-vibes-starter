# frozen_string_literal: true

require 'spec_helper'
ENV['RAILS_ENV'] ||= 'test'
ENV['OPENAI_API_KEY'] ||= 'test-openai-key'
ENV['ANTHROPIC_API_KEY'] ||= 'test-anthropic-key'
require_relative '../config/environment'
abort("The Rails environment is running in production mode!") if Rails.env.production?
require 'rspec/rails'

begin
  ActiveRecord::Migration.maintain_test_schema!
rescue ActiveRecord::PendingMigrationError => e
  abort e.to_s.strip
end

# Ensure routes are loaded for Devise integration helpers
Rails.application.reload_routes!

RSpec.configure do |config|
  config.fixture_paths = [ Rails.root.join('spec/fixtures') ]
  config.global_fixtures = :all
  config.use_transactional_fixtures = true
  config.infer_spec_type_from_file_location!
  config.filter_rails_from_backtrace!

  # Include Devise test helpers for request specs
  config.include Devise::Test::IntegrationHelpers, type: :request
end
