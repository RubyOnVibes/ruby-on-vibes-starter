Rails.configuration.x.llm.tool_options = { rounds: 25, calls: 50 }.freeze

RubyLLM.configure do |config|
  # Prompts, tool arguments, and responses can contain private workspace data.
  config.log_bodies = false
  # RubyLLM bounds tool results before they can exhaust a conversation's window.
  config.context_budget = { per_result: 0.25, per_request: 0.7 }
  default_model_set = nil

  # Anthropic support: use API key if present, otherwise use platform proxy if possible
  if ENV["ANTHROPIC_API_KEY"].present?
    config.anthropic_api_key = ENV["ANTHROPIC_API_KEY"]
    config.default_model = "claude-sonnet-4-6"  unless default_model_set
    default_model_set = true
  elsif ENV["USE_MOUNTED_VIBES"] == "true" && ENV["VIBES_AI_PROXY_URL"].present?
    config.anthropic_api_base = ENV["VIBES_AI_PROXY_URL"]
    config.anthropic_api_key = ENV["VIBES_API_TOKEN"]
    config.default_model = "claude-sonnet-4-6"  unless default_model_set
    default_model_set = true
  end

  # OpenAI support: ENV config only. no proxy support yet.
  if ENV["OPENAI_API_KEY"].present?
    config.openai_api_key = ENV["OPENAI_API_KEY"]

    config.default_model = "gpt-5-nano" unless default_model_set
    default_model_set ||= true
  end

  # Select a supported model without editing the template. Its provider is
  # resolved by RubyLLM; configure that provider's credentials above.
  config.default_model = ENV["LLM_MODEL"] if ENV["LLM_MODEL"].present?
end
