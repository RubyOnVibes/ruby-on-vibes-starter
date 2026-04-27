# frozen_string_literal: true

##
# ChatContext - Structured LLM context for Chat records
#
# Provides schema-driven serialization for chats when mentioned.
# Useful for cross-chat references and chat summaries.
#
class ChatContext < RecordContext
  schema do
    description "A conversation between a user and an AI assistant"
    
    string :id, description: "Prefixed chat ID (chat_xxx)"
    string :name, description: "Chat display name or title"
    string :path, description: "Chat path (e.g., /o/org_xxx/chat_xxx)"
    integer :messages_count, 
      description: "Number of messages in the chat",
      minimum: 0
    string :created_at, description: "When the chat was created (ISO8601)"
    string :updated_at, description: "When the chat was last updated (ISO8601)"
    
    object :member, description: "Chat owner (member)" do
      string :id, description: "Member ID"
      string :user_name, description: "User's name"
    end
    
    object :model, required: false, description: "AI model used in this chat" do
      string :id, description: "Model identifier"
      string :name, description: "Model display name"
      string :provider, description: "Model provider (openai, anthropic, etc)"
    end
  end
  
  ##
  # Create context from Chat record
  #
  # @param chat [Chat] The chat to serialize
  # @return [ChatContext] Context instance
  #
  def self.from_record(chat)
    model_data = if chat.model
      {
        id: chat.model.model_id,
        name: chat.model.name,
        provider: chat.model.provider
      }
    else
      nil
    end
    
    new(
      id: chat.to_param,
      path: Rails.application.routes.url_helpers.chat_path(chat),
      name: chat.name.presence || "Chat #{chat.to_param}",
      messages_count: chat.messages.count,
      created_at: chat.created_at.iso8601,
      updated_at: chat.updated_at.iso8601,
      member: {
        id: chat.member.to_param,
        user_name: [chat.member.user.first_name, chat.member.user.last_name].compact.join(' ')
      },
      model: model_data
    ).tap do |context|
      # Remove model key if nil (matches required: false in schema)
      context.data.delete(:model) if model_data.nil?
    end
  end
  
  ##
  # Generate human-readable summary
  # Used for inline mentions and logging
  #
  def summary
    model_text = data[:model] ? " (using #{data[:model][:name]})" : ""
    "Chat '#{data[:name]}' with #{data[:messages_count]} messages#{model_text}"
  end
end

