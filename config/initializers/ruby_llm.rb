RubyLLM.configure do |config|
  default_model_set = nil

  # Anthropic support: use API key if present, otherwise use platform proxy if possible
  if ENV["ANTHROPIC_API_KEY"].present?
    config.anthropic_api_key = ENV["ANTHROPIC_API_KEY"]
    config.default_model = "claude-sonnet-4-6"
    default_model_set = true
  elsif ENV["USE_MOUNTED_VIBES"] == "true" && ENV["VIBES_AI_PROXY_URL"].present?
    config.anthropic_api_base = ENV["VIBES_AI_PROXY_URL"]
    config.anthropic_api_key = ENV["VIBES_API_TOKEN"]
    config.default_model = "claude-sonnet-4-6"
    default_model_set = true
  end

  # OpenAI support: ENV config only. no proxy support yet.
  if ENV["OPENAI_API_KEY"].present?
    config.openai_api_key = ENV["OPENAI_API_KEY"]

    config.default_model = "gpt-4.1-nano" unless default_model_set
    default_model_set ||= true
  end

  config.use_new_acts_as = true
end
