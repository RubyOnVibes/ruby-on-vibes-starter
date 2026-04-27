# frozen_string_literal: true

##
# Examples::SideEffectsExerciseTool - Reference harness for all effect-tracking helpers
#
# Creates an AgentTask and enqueues Examples::SideEffectsExerciseJob which exercises
# every effect-tracking helper on AgentTaskJob:
#   - track_create (Workspace)
#   - track_update (Workspace)
#   - track_attach has_one_attached (Workspace avatar)
#   - track_detach has_one_attached (Workspace avatar)
#   - track_attach has_many_attached (task attachments)
#   - track_detach has_many_attached (task attachment by filename)
#   - track_effect custom (simulated notification)
#   - track_enqueue_subtask (spawns an echo subtask)
#   - track_destroy (Workspace)
#
# Use this to verify:
#   1. All effect types render correctly on the task show page
#   2. has_one_attached and has_many_attached both work for attach/detach
#   3. Progress bar advances through each step
#   4. Cancel button stops execution mid-run
#   5. Attachments appear/disappear correctly (CSV remains, TXT detached)
#   6. Subtask appears as a second task; chat waits for both to complete
#
module Examples
  class SideEffectsExerciseTool < RubyLLM::Tool
    description "Run a test background task that exercises every effect-tracking side effect " \
                "(create, update, attach, detach, notify, enqueue subtask, destroy). " \
                "Also spawns an echo subtask to prove the subtask pattern. " \
                "Use this to verify the full agent task effects pipeline end-to-end."

    params do
      integer :step_delay, description: "Seconds to pause between each step for visibility (default: 1, max: 5)", required: false
    end

    attr_reader :chat, :sender_user, :sender_member, :sender_workspace

    def initialize(chat:, sender_user: nil, sender_member: nil, sender_workspace: nil)
      @chat = chat
      @sender_user = sender_user
      @sender_member = sender_member
      @sender_workspace = sender_workspace
    end

    def execute(step_delay: nil)
      step_delay = [[step_delay.to_i, 1].max, 5].min if step_delay.present?
      step_delay ||= 1

      task = AgentTask.create!(
        chat: @chat,
        workspace: @sender_workspace,
        member: @sender_member,
        kind: "side_effects_exercise",
        metadata: { step_delay: step_delay }
      )

      Examples::SideEffectsExerciseJob.perform_later(task.id)

      {
        task_id: task.to_param,
        message: "Side effects exercise started. It will walk through 9 effects (create, update, attach, detach, notify, destroy) with #{step_delay}s pauses between steps.",
        step_delay: step_delay
      }
    end
  end
end
