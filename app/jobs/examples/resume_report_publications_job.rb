# frozen_string_literal: true

module Examples
  # Opt in alongside ReportPublisherAgent. This delivers committed business
  # intent; RubyLLM remains the only owner of paused tool/conversation state.
  class ResumeReportPublicationsJob < ApplicationJob
    queue_as :agents

    def perform
      ReportPublication.status_queued.find_each(&:recover!)
    end
  end
end
