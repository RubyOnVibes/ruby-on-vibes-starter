# frozen_string_literal: true

module Examples
  # RubyLLM persists this native task's data on the tool call. Reconstructing the
  # subclass lets native cancellation stop the application's pending operation.
  class ReportPublicationTask < RubyLLM::Task
    def cancel
      ReportPublication.find_by(id: data.fetch("report_id"))&.cancel!
      self
    end
  end
end
