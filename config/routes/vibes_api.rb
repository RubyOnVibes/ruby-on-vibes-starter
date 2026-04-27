namespace :vibes do
  # Vibes API is the hosted platform's sync surface (file writes, hot reload, git pull).
  # Opt-IN by design: set VIBES_API_ENABLED=true only when running under the platform.
  # See docs/vibes-api.md.
  break unless ENV['VIBES_API_ENABLED'] == 'true'

  namespace :api do
    get    "health",       to: "api#health"
    post   "reload",       to: "api#reload"
    post   "git_pull",     to: "api#git_pull"
    post   "users/admins", to: "users#create_admins"
  end
end