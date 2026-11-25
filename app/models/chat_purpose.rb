# frozen_string_literal: true

# A persisted purpose is an application-owned name, never a Ruby class supplied
# by a request. Keeping class resolution here also works with Rails reloading.
class ChatPurpose
  class UnknownPurpose < ArgumentError; end
  class InvalidContext < ArgumentError; end

  def self.registry
    { "assistant" => ChatAgent }
  end

  def self.keys
    registry.keys
  end

  def self.agent_class_for(purpose)
    registry.fetch(purpose.to_s) do
      raise UnknownPurpose, "Unknown chat purpose: #{purpose.inspect}"
    end
  end

  def self.bind(chat:, run:, user_message: nil, options: {})
    raise InvalidContext, "The run belongs to another chat" unless run.chat_id == chat.id
    if user_message && user_message.chat_id != chat.id
      raise InvalidContext, "The message belongs to another chat"
    end

    context = ChatAgentContext.new(chat: chat, run: run, user_message: user_message, options: options)
    unless context.member && chat.member_exists?(context.member)
      raise InvalidContext, "The initiating member no longer has access to this chat"
    end
    if user_message&.member_id && user_message.member_id != context.member.id
      raise InvalidContext, "The message belongs to another initiating member"
    end

    # Bind the scoped record, rather than using Agent.find's unscoped lookup.
    # Runtime instructions are rebuilt each time without rewriting history.
    configured_chat = agent_class_for(chat.purpose).new(
      chat: chat, inputs: { run_context: context }, persist_instructions: false
    ).chat

    # Provider/billing changes are explicit application opt-ins. Without an
    # override, a purpose keeps the fallbacks declared on its native agent.
    fallback_models = ENV.fetch("LLM_FALLBACK_MODELS", "").split(",").map(&:strip).reject(&:blank?)
    configured_chat.with_fallbacks(*fallback_models) if fallback_models.any?
    configured_chat
  end
end
