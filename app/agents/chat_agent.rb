# frozen_string_literal: true

# Default purpose for the application's persisted conversations. Application
# features can replace these declarations in their own ApplicationAgent class.
class ChatAgent < ApplicationAgent
  tools { run_context.tools }

  # Keep the reusable prefix ahead of mentions, participants and task results.
  # with_caching(false) suppresses explicit boundaries unless opted in.
  instructions(cache_until_here: true) { run_context.stable_instructions }
  instructions(append: true, persist: false) { run_context.dynamic_instructions }
  caching { ENV["LLM_PROMPT_CACHING"] == "true" ? {} : false }

  # Files belong to the shared conversation. Usage remains owned by ChatRun;
  # neither this agent nor the file store overrides chat.with_owner.
  file_store
end
