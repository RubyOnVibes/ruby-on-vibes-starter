# frozen_string_literal: true

class ResumeAgentDeliveriesJob < ApplicationJob
  queue_as :agents

  def perform
    AgentDelivery.due.find_each(&:dispatch!)
  end
end
