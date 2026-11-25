class ApplicationAgent < RubyLLM::Agent
  chat_class Chat
  inputs :run_context
  tool_options { Rails.configuration.x.llm.tool_options }
end
