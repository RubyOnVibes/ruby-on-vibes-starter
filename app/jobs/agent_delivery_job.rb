# frozen_string_literal: true

class AgentDeliveryJob < ApplicationJob
  queue_as :agents
  discard_on ActiveRecord::RecordNotFound

  def perform(delivery_id)
    AgentDelivery.find(delivery_id).deliver!
  end
end
