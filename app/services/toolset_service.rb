##
# ToolsetService - Registry of all tools available to the AI agent in chat.
#
# Tools are the capabilities the LLM can invoke during a conversation.
# There are two kinds of tools:
#
#   1. INLINE tools — run inside the chat fiber, return results immediately.
#      Good for fast lookups, simple operations (< ~10 seconds).
#      Example: CurrentDateTimeTool, WebFetchTool
#
#   2. TASK-TRIGGERING tools — create an AgentTask and enqueue a background job.
#      Good for long-running work, retries, progress tracking.
#      Example: Examples::EchoAgentTaskTool → creates AgentTask → enqueues Examples::EchoAgentTaskJob
#      (See app/tools/examples/ and app/jobs/examples/ for paired reference tools + jobs.)
#
# To add a new tool:
#   1. Create your tool class in app/tools/ (subclass RubyLLM::Tool)
#   2. Add it to the #tool_classes array below
#   3. If it triggers a background task, also create a job in app/jobs/ (subclass AgentTaskJob)
#
# See docs/building_with_agents.md for the full guide.
#
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

  # Configure the list of tool classes to instantiate.
  # Add your custom tools here - they'll be available to the LLM in chat.
  #
  # If the chat belongs to an Agent with custom tool_config, those tool classes
  # are used instead of the defaults (agent task management tools are always included).
  def tool_classes
    # Check for agent-specific tool config
    if @chat && (agent = @chat.agent)&.configured_tool_classes
      tools = agent.configured_tool_classes

      # Always include agent task management tools
      if RubyOnVibes.agent_tasks?
        tools.push(
          AgentTaskStatusTool,
          CancelAgentTaskTool,
          ListAgentTasksTool
        )
      end

      return tools.uniq
    end

    tools = [
      CurrentDateTimeTool,      # Returns current date/time in user's timezone
      RandomNumberTool,         # Generates true random numbers (no network needed)
      WebFetchTool,             # Fetches and extracts text from web pages
    ]

    # Agent task tools — gated behind agent_tasks being enabled
    if RubyOnVibes.agent_tasks?
      tools.push(
        AgentTaskStatusTool,    # Check status/result of an agent task
        CancelAgentTaskTool,    # Cancel a running agent task
        ListAgentTasksTool      # List agent tasks in the chat
      )

      # Reference/demo tools for verifying the agent task pipeline end-to-end.
      # Live in app/tools/examples/ and app/jobs/examples/ — copy them as starting
      # points for your own tools. Available in dev/test by default; set
      # VIBES_DEBUG_TOOLS=true to enable in production.
      if RubyOnVibes.debug_tools?
        tools.push(
          Examples::EchoAgentTaskTool,         # Creates a task with progress updates
          Examples::FailingAgentTaskTool,      # Creates a task that fails to test retries
          Examples::SideEffectsExerciseTool    # Exercises all effect-tracking helpers end-to-end
        )
      end
    end

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