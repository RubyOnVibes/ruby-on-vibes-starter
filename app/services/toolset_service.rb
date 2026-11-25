# frozen_string_literal: true

# Allowlisted application tools for the default assistant. Feature purposes can
# declare tools directly using the native Agent DSL.
class ToolsetService
  def initialize(user_message: nil, chat: nil, sender_user:, sender_member:, sender_workspace:)
    @user_message = user_message
    @chat = chat || user_message&.chat

    # Context about who SENT the message we're responding to.
    # (may be from a different workspace than the chat's workspace if cross-workspace members)
    @sender_user = sender_user
    @sender_member = sender_member
    @sender_workspace = sender_workspace
  end

  # nil means the application's defaults; [] means no application tools.
  # An explicit selection never silently regains task-management capabilities.
  def tool_classes
    configured = @chat&.agent&.configured_tool_classes
    configured.nil? ? self.class.default_tool_classes : configured
  end

  class InvalidToolConfiguration < ArgumentError; end

  # Register additional classes here when they may be selected by persisted
  # Agents but should not be enabled for every default chat. Request/database
  # strings are looked up in this code-owned allowlist, never constantized.
  def self.additional_tool_classes
    []
  end

  def self.registry
    (default_tool_classes + additional_tool_classes).uniq.index_by(&:name)
  end

  def self.resolve(names)
    return nil if names.nil?
    unless names.is_a?(Array) && names.all? { |name| name.is_a?(String) }
      raise InvalidToolConfiguration, "Tool configuration must be an array of registered names"
    end

    allowed = registry
    names.uniq.map do |name|
      allowed.fetch(name) { raise InvalidToolConfiguration, "Tool is not registered or enabled: #{name}" }
    end
  end

  # Add application-wide tools here. Feature gates also constrain the registry
  # so a persisted Agent cannot bypass disabled reference capabilities.
  def self.default_tool_classes
    tools = [
      CurrentDateTimeTool,      # Returns current date/time in user's timezone
      RandomNumberTool,         # Generates true random numbers (no network needed)
      WebFetchTool             # Fetches and extracts text from web pages
    ]

    tools << Examples::RenameChatTool if RubyOnVibes.debug_tools?

    tools
  end

  def tools
    # Instantiate each tool with chat and sender context (chat.workspace and sender_workspace differ when cross-workspace senders):
    tool_classes.map do |tool_class|
      tool_class.new(
        chat: @chat,
        sender_user: @sender_user,
        sender_member: @sender_member,
        sender_workspace: @sender_workspace
      )
    end
  end
end
