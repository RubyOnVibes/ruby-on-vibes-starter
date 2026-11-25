class ApplicationAgent < RubyLLM::Agent
  chat_class Chat
  tool_options { Rails.configuration.x.llm.tool_options }
end
