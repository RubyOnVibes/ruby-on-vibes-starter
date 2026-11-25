# frozen_string_literal: true

# Default purpose for the application's persisted conversations. Application
# features can replace these declarations in their own ApplicationAgent class.
class ChatAgent < ApplicationAgent
  tools { run_context.tools }

  # Cache only application policy; record data stays in user/tool messages.
  instructions(cache_until_here: true) { run_context.stable_instructions }
  caching { ENV["LLM_PROMPT_CACHING"] == "true" ? {} : false }

  # Files belong to the shared conversation. Usage remains owned by ChatRun;
  # neither this agent nor the file store overrides chat.with_owner.
  file_store
end
