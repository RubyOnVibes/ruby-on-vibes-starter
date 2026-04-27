# frozen_string_literal: true

##
# Examples::FailingAgentTaskTool - Reference harness for agent task failure and retry
#
# Creates an AgentTask that is designed to fail, testing:
#   1. Retry behavior (task goes pending → running → fails → pending → running → ...)
#   2. Attempts tracking on the task record
#   3. Final failure after exhausting retries
#   4. Failed status icon in the UI
#
module Examples
  class FailingAgentTaskTool < RubyLLM::Tool
    description "Run a test background task that intentionally fails to test error handling and retries. " \
                "The task will retry up to 3 times with a 5-second delay between attempts."

    params do
      string :message, description: "Error message to simulate (default: 'Simulated failure for testing')", required: false
    end

    attr_reader :chat, :sender_user, :sender_member, :sender_workspace

    def initialize(chat:, sender_user: nil, sender_member: nil, sender_workspace: nil)
      @chat = chat
      @sender_user = sender_user
      @sender_member = sender_member
      @sender_workspace = sender_workspace
    end

    def execute(message: nil)
      message ||= "Simulated failure for testing"

      task = AgentTask.create!(
        chat: @chat,
        workspace: @sender_workspace,
        member: @sender_member,
        kind: "failing_test",
        metadata: { error_message: message }
      )

      Examples::FailingAgentTaskJob.perform_later(task.id)

      {
        task_id: task.to_param,
        message: "Failing test task started. It will attempt 3 times with 5-second delays, then fail permanently."
      }
    end
  end
end
