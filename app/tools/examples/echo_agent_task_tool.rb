# frozen_string_literal: true

##
# Examples::EchoAgentTaskTool - Reference harness for the agent task lifecycle
#
# This is a reference implementation showing how to build a Tool that
# triggers a background agent task. The pattern is:
#
#   1. Tool#execute creates an AgentTask record (status: pending)
#   2. Tool enqueues the matching Job with task.id
#   3. Tool returns a hash with task_id so the LLM can reference it
#   4. The job runs in the background, updates progress, completes
#   5. Frontend polls the task and shows progress to the user
#   6. On the next chat turn, the agent automatically sees the result
#
# To build your own tool + task pair:
#   - Copy this tool's structure (create AgentTask, enqueue job, return task_id)
#   - Create a matching AgentTaskJob subclass (see Examples::EchoAgentTaskJob)
#   - Register the tool in ToolsetService#tool_classes
#
# See also: Examples::EchoAgentTaskJob (the job this tool triggers)
# See also: docs/building_with_agents.md (full guide)
#
module Examples
  class EchoAgentTaskTool < RubyLLM::Tool
    description "Run a test background task that simulates work with progress updates. " \
                "Use this to verify agent tasks are working correctly. " \
                "Takes an optional message and duration."

    params do
      string :message, description: "A message to echo back in the result (default: 'Hello from EchoAgentTask')", required: false
      integer :duration, description: "How long the task should run in seconds (default: 10, max: 60)", required: false
    end

    attr_reader :chat, :sender_user, :sender_member, :sender_workspace

    def initialize(chat:, sender_user: nil, sender_member: nil, sender_workspace: nil)
      @chat = chat
      @sender_user = sender_user
      @sender_member = sender_member
      @sender_workspace = sender_workspace
    end

    def execute(message: nil, duration: nil)
      message ||= "Hello from EchoAgentTask"
      duration = [[duration.to_i, 1].max, 60].min if duration.present?
      duration ||= 10

      task = AgentTask.create!(
        chat: @chat,
        workspace: @sender_workspace,
        member: @sender_member,
        kind: "echo_test",
        metadata: { message: message, duration: duration }
      )

      Examples::EchoAgentTaskJob.perform_later(task.id)

      {
        task_id: task.to_param,
        message: "Echo task started. It will run for #{duration} seconds with progress updates.",
        duration: duration
      }
    end
  end
end
