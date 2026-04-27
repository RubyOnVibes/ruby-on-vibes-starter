# frozen_string_literal: true

# Configure Turbo::Streams::ActionBroadcastJob to use async_job
# This ensures broadcasts run inline in the Falcon process (same as ActionCable)
# Without this, broadcasts go to SolidQueue (separate process) and can't reach ActionCable
Rails.application.config.after_initialize do
  Turbo::Streams::ActionBroadcastJob.queue_adapter = :async_job
end

