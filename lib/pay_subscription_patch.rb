module PaySubscriptionPatch
  extend ActiveSupport::Concern

  included { has_prefix_id :sub }

  def plan
    @plan ||= Plan.where(stripe_id: processor_plan).first
  end

  def amount
    if quantity > 0
      plan.amount * quantity
    else
      plan.amount
    end
  end

  def currency
    plan&.currency
  end
end