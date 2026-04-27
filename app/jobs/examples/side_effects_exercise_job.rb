# frozen_string_literal: true

##
# Examples::SideEffectsExerciseJob - Exercises every effect-tracking helper end-to-end
#
# Walks through all AgentTaskJob effect helpers in sequence:
#   1.  track_create            — creates a Workspace
#   2.  track_update            — updates the Workspace name
#   3.  track_attach            — attaches avatar to Workspace (has_one_attached)
#   4.  track_detach            — detaches avatar from Workspace (has_one_attached)
#   5.  track_attach            — attaches CSV to task (has_many_attached)
#   6.  track_attach            — attaches TXT to task (has_many_attached)
#   7.  track_detach            — detaches TXT from task by filename (has_many_attached)
#   8.  track_effect            — logs a custom "notified" effect
#   9.  track_enqueue_subtask   — spawns an echo subtask (proves subtask pattern)
#   10. track_destroy           — destroys the Workspace
#
# Each step updates progress and pauses briefly so the UI is observable.
# The exercise workspace is created and destroyed within the run — no
# persistent side effects remain after completion (except the subtask,
# which runs independently and the chat waits for it before summarizing).
#
module Examples
  class SideEffectsExerciseJob < AgentTaskJob
    STEPS = [
      { pct: 8,   text: "Creating exercise workspace..." },
      { pct: 18,  text: "Updating workspace..." },
      { pct: 28,  text: "Attaching avatar (has_one)..." },
      { pct: 38,  text: "Detaching avatar (has_one)..." },
      { pct: 48,  text: "Attaching CSV to task (has_many)..." },
      { pct: 56,  text: "Attaching TXT to task (has_many)..." },
      { pct: 64,  text: "Detaching TXT from task by filename (has_many)..." },
      { pct: 72,  text: "Logging custom notification effect..." },
      { pct: 84,  text: "Enqueuing echo subtask..." },
      { pct: 95,  text: "Destroying exercise workspace..." },
    ].freeze

    private

    def execute(task)
      delay = task.metadata&.dig("step_delay") || 1
      user = task.member.user
      effects_completed = 0

      # Step 1: track_create — create a Workspace
      step(task, 0, delay)
      return cancelled_result(effects_completed) if cancelled?

      workspace = track_create(Workspace,
        description: "Created exercise workspace for side effects test",
        name: "Exercise #{Time.current.to_i}",
        owner: user,
        is_team_workspace: false)
      effects_completed += 1

      # Step 2: track_update — rename the workspace
      step(task, 1, delay)
      return cleanup_and_cancel(workspace, effects_completed) if cancelled?

      track_update(workspace,
        description: "Updated exercise workspace name",
        name: "Exercise (updated) #{Time.current.to_i}")
      effects_completed += 1

      # Step 3: track_attach has_one_attached — avatar on workspace
      step(task, 2, delay)
      return cleanup_and_cancel(workspace, effects_completed) if cancelled?

      track_attach(workspace, :avatar,
        description: "Attached exercise avatar to workspace",
        io: StringIO.new(tiny_png),
        filename: "exercise_avatar.png",
        content_type: "image/png")
      effects_completed += 1

      # Step 4: track_detach has_one_attached — avatar from workspace
      step(task, 3, delay)
      return cleanup_and_cancel(workspace, effects_completed) if cancelled?

      track_detach(workspace, :avatar,
        description: "Detached exercise avatar from workspace")
      effects_completed += 1

      # Step 5: track_attach has_many_attached — CSV on task
      step(task, 4, delay)
      return cleanup_and_cancel(workspace, effects_completed) if cancelled?

      track_attach(task, :attachments,
        description: "Attached exercise CSV data to task",
        io: StringIO.new("id,name,status\n1,Widget A,active\n2,Widget B,inactive\n3,Widget C,active\n"),
        filename: "exercise_data.csv",
        content_type: "text/csv")
      effects_completed += 1

      # Step 6: track_attach has_many_attached — TXT on task (will be detached)
      step(task, 5, delay)
      return cleanup_and_cancel(workspace, effects_completed) if cancelled?

      track_attach(task, :attachments,
        description: "Attached temporary TXT file to task (will be detached)",
        io: StringIO.new("This file is temporary and will be detached in the next step."),
        filename: "exercise_temp.txt",
        content_type: "text/plain")
      effects_completed += 1

      # Step 7: track_detach has_many_attached — TXT from task by filename
      step(task, 6, delay)
      return cleanup_and_cancel(workspace, effects_completed) if cancelled?

      track_detach(task, :attachments, "exercise_temp.txt",
        description: "Detached temporary TXT file from task by filename")
      effects_completed += 1

      # Step 8: track_effect — custom "notified" effect
      step(task, 7, delay)
      return cleanup_and_cancel(workspace, effects_completed) if cancelled?

      track_effect("notified",
        target: user,
        description: "Simulated email notification to #{user.email || 'workspace owner'}",
        details: { channel: "email", recipient: user.email, subject: "Side effects exercise completed" })
      effects_completed += 1

      # Step 9: track_enqueue_subtask — spawn an echo task as a subtask
      step(task, 8, delay)
      return cleanup_and_cancel(workspace, effects_completed) if cancelled?

      subtask = track_enqueue_subtask(Examples::EchoAgentTaskJob,
        kind: "echo_test",
        description: "Spawned echo subtask to prove subtask pattern",
        metadata: { message: "Hello from subtask of side_effects_exercise", duration: 3 })
      effects_completed += 1

      # Step 10: track_destroy — clean up the workspace
      step(task, 9, delay)
      return cleanup_and_cancel(workspace, effects_completed) if cancelled?

      track_destroy(workspace,
        description: "Cleaned up exercise workspace")
      effects_completed += 1

      {
        effects_completed: effects_completed,
        effects_exercised: %w[created updated attached_has_one detached_has_one attached_has_many detached_has_many notified enqueued_subtask deleted],
        subtask_id: subtask.to_param,
        remaining_attachments: task.attachments.count,
        completed_at: Time.current.iso8601,
        summary: "All #{effects_completed} effect-tracking helpers exercised successfully. " \
                 "CSV attachment remains on task; TXT was detached. Exercise workspace was created and destroyed. " \
                 "Echo subtask #{subtask.to_param} is running independently."
      }
    end

    # Advance progress and pause for observability
    def step(task, index, delay)
      info = STEPS[index]
      task.update_progress!(info[:pct], info[:text])
      sleep delay
    end

    # Clean up the workspace if cancelled mid-run, then return result
    def cleanup_and_cancel(workspace, effects_completed)
      workspace.destroy if workspace&.persisted?
      cancelled_result(effects_completed)
    end

    def cancelled_result(effects_completed)
      { effects_completed: effects_completed, cancelled: true }
    end

    # Minimal valid 1x1 pixel transparent PNG (67 bytes)
    def tiny_png
      [
        0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A, # PNG signature
        0x00, 0x00, 0x00, 0x0D, 0x49, 0x48, 0x44, 0x52, # IHDR chunk
        0x00, 0x00, 0x00, 0x01, 0x00, 0x00, 0x00, 0x01, # 1x1
        0x08, 0x06, 0x00, 0x00, 0x00, 0x1F, 0x15, 0xC4, # RGBA, filters
        0x89, 0x00, 0x00, 0x00, 0x0A, 0x49, 0x44, 0x41, # IDAT chunk
        0x54, 0x78, 0x9C, 0x62, 0x00, 0x00, 0x00, 0x02, # compressed data
        0x00, 0x01, 0xE5, 0x27, 0xDE, 0xFC, 0x00, 0x00, # ...
        0x00, 0x00, 0x49, 0x45, 0x4E, 0x44, 0xAE, 0x42, # IEND chunk
        0x60, 0x82
      ].pack("C*")
    end
  end
end
