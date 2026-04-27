# frozen_string_literal: true

InertiaRails.configure do |config|
  config.ssr_enabled = ENV['ENABLE_SSR'] == 'true' && ViteRuby.config.ssr_build_enabled
  config.version = ViteRuby.digest
  config.always_include_errors_hash = true
end