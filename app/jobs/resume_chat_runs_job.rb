# frozen_string_literal: true

# Recover missing delivery, expired native claims and due task polls. Native
# claims serialize the conversation loop, including duplicate queue deliveries.
class ResumeChatRunsJob < ApplicationJob
  queue_as :agents

  def perform
    ChatRun.active.where(status: [:pending, :running, :awaiting_tasks]).find_each do |run|
      run.recover!
    rescue ActiveRecord::RecordNotFound
      # A user deleted the chat while the sweep was running.
      next
    end
  end
end
