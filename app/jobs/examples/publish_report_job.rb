# frozen_string_literal: true

module Examples
  class PublishReportJob < ApplicationJob
    queue_as :agents
    discard_on ActiveRecord::RecordNotFound

    def perform(publication_id)
      ReportPublication.find(publication_id).publish!
    end
  end
end
