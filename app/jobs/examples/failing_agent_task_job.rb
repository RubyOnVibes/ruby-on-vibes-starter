# frozen_string_literal: true

##
# Examples::FailingAgentTaskJob - Reference harness for agent task failure and retry
#
# Always raises after showing some progress, to test:
# - Retry behavior with attempts tracking
# - Progress reset between attempts
# - Final failure after max_attempts exhausted
#
module Examples
  class FailingAgentTaskJob < AgentTaskJob
    private

    def max_attempts
      3
    end

    def retry_delay(_attempt)
      5.seconds
    end

    def execute(task)
      error_message = task.metadata&.dig("error_message") || "Simulated failure for testing"

      # Show some progress before failing
      task.update_progress!(25, "Attempt #{task.attempts}: Starting work...")
      sleep 2
      return if cancelled?

      task.update_progress!(50, "Attempt #{task.attempts}: Processing...")
      sleep 2
      return if cancelled?

      task.update_progress!(75, "Attempt #{task.attempts}: About to fail...")
      sleep 1

      raise StandardError, error_message
    end
  end
end
