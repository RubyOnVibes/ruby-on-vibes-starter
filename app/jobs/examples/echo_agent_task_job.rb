# frozen_string_literal: true

##
# Examples::EchoAgentTaskJob - Reference harness for agent task background execution
#
# This is a reference implementation showing how to build an AgentTaskJob.
# It simulates a long-running operation with progress updates.
#
# Key patterns demonstrated:
#   - Reading config from task.metadata (message, duration)
#   - Updating progress with task.update_progress!(pct, text)
#   - Checking for cancellation with `break if cancelled?`
#   - Returning a result hash that becomes task.result
#
# To build your own agent task, copy this pattern:
#   1. Subclass AgentTaskJob
#   2. Implement #execute(task) — read from task.metadata, update progress, return result hash
#   3. Create a matching Tool that creates the AgentTask and enqueues this job
#   4. Register the tool in ToolsetService#tool_classes
#
# See also: Examples::EchoAgentTaskTool (the tool that triggers this job)
# See also: docs/building_with_agents.md (full guide)
#
module Examples
  class EchoAgentTaskJob < AgentTaskJob
    STEPS = [
      "Initializing...",
      "Processing data...",
      "Crunching numbers...",
      "Analyzing results...",
      "Generating report...",
      "Finalizing..."
    ].freeze

    private

    def execute(task)
      duration = task.metadata&.dig("duration") || 10
      message = task.metadata&.dig("message") || "Hello from EchoAgentTask"

      elapsed = 0
      while elapsed < duration
        break if cancelled?

        elapsed += 1
        pct = ((elapsed.to_f / duration) * 100).round
        step_index = ((elapsed.to_f / duration) * (STEPS.length - 1)).floor
        step_text = STEPS[[step_index, STEPS.length - 1].min]

        task.update_progress!(pct, "#{step_text} (#{elapsed}/#{duration}s)")
        sleep 1
      end

      {
        message: message,
        duration: duration,
        completed_at: Time.current.iso8601,
        echo: "Task completed successfully after #{duration} seconds."
      }
    end
  end
end
