# frozen_string_literal: true

module Examples
  # A small, reversible reference implementation for human-approved writes.
  # It is exposed only with the template's debug tools; copy the pattern for
  # consequential application actions such as sending, publishing or deleting.
  class RenameChatTool < RubyLLM::Tool
    description <<~DESC
      Renames the current chat. This changes persisted application data and
      therefore always requires explicit human approval before execution.
    DESC

    parameters do
      string :title, description: "New chat title (1-80 characters)", required: true
    end

    requires_approval

    def initialize(chat:, sender_user: nil, sender_member: nil, sender_workspace: nil)
      @chat = chat
      @sender_user = sender_user
      @sender_member = sender_member
      @sender_workspace = sender_workspace
    end

    def execute(title:)
      return { error: "Only the chat owner can rename this chat." } unless @chat.owner?(@sender_member)

      normalized_title = title.to_s.strip
      return { error: "Title must be between 1 and 80 characters." } unless normalized_title.length.between?(1, 80)

      previous_title = @chat.name
      @chat.update!(name: normalized_title)

      {
        changed: true,
        previous_title: previous_title,
        title: @chat.name,
        chat_id: @chat.to_param
      }
    end
  end
end
