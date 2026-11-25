# frozen_string_literal: true

module Examples
  class PublishReportTool < RubyLLM::Tool
    description "Publish an already prepared report after human confirmation. Use its application-provided report ID."
    requires_approval

    parameters do
      integer :report_id, description: "ID of the immutable prepared report", required: true
    end

    def initialize(chat:, run:)
      @chat = chat
      @run = run
    end

    def execute(report_id:)
      report = authorized_report(report_id)
      report.request_publication!(run: @run)
      result_or_task(report)
    end

    def resume(task, report_id:)
      raise ArgumentError, "Task does not match report" unless task.data.fetch("report_id") == report_id
      report = authorized_report(report_id)
      report.dispatch_if_pending!
      result_or_task(report)
    end

    def task(state, tool_call: nil)
      ReportPublicationTask.load(state, tool_call: tool_call)
    end

    private

    def authorized_report(id)
      report = ReportPublication.where(chat_id: @chat.id).find(id)
      report.authorize_run!(@run)
      report
    end

    def result_or_task(report)
      return report.result unless report.status_queued?
      ReportPublicationTask.new(status: :working, poll_interval: 5,
        status_message: "Publishing the approved report", data: { "report_id" => report.id })
    end
  end
end
