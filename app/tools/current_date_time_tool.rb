# frozen_string_literal: true

class CurrentDateTimeTool < RubyLLM::Tool
  description <<~DESC
    Returns current date and time, optionally in a specific timezone.

    WHEN TO USE THIS:
    - When the user asks what time it is
    - When you need the current date for scheduling, deadlines, or time-sensitive responses
    - When converting times between timezones

    The tool respects the user's configured timezone by default.
  DESC

  params do
    string :timezone, description: "IANA timezone (e.g., 'America/New_York', 'Europe/London'). Defaults to user's timezone or UTC.", required: false
    string :format, description: "Output format: 'full' (default), 'date', 'time', or 'iso8601'", required: false
  end

  attr_reader :chat, :sender_user, :sender_member, :sender_workspace

  # @param chat [Chat] The chat the message was sent in
  # @param sender_user [User] The user who sent the message
  # @param sender_member [Member] The user's member record who sent the message
  # @param sender_workspace [Workspace] The workspace the sender is in
  # 
  # NOTE: This is an example tool.
  # The following parameters are not required for all tools, but it is good practice to include them for consistency.
  # When dealing with multiple members and multiple workspaces, it is important to know the context of the message and the chat.
  # 
  def initialize(chat:, sender_user: nil, sender_member: nil, sender_workspace: nil)
    @chat = chat
    @chat_workspace = chat.workspace
    @sender_user = sender_user
    @sender_member = sender_member
    @sender_workspace = sender_workspace

    # Chat members may be from a different workspace than the chat was created in.
    @same_workspace = sender_workspace.present? && sender_workspace == @chat_workspace
  end

  def execute(timezone: nil, format: nil)
    tz = timezone || @sender_user&.time_zone || "UTC"
    time = Time.current.in_time_zone(tz)

    result = case format&.downcase
    when "date"
      time.strftime("%Y-%m-%d")
    when "time"
      time.strftime("%H:%M:%S %Z")
    when "iso8601"
      time.iso8601
    else # "full" or nil
      time.strftime("%Y-%m-%d %H:%M:%S %Z")
    end

    { current_time: result, timezone: tz }
  rescue ArgumentError => e
    { error: "Invalid timezone: #{timezone}" }
  rescue => e
    { error: e.message }
  end
end
