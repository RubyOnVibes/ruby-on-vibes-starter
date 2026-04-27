module PaymentsHelper
  # Payment and Subscription Management
  # Consolidates: PlansHelper (domain-specific payment/billing logic)

  # ==================== PLAN FORMATTING ====================
  
  # Formats the billing interval for display
  # @example
  #   <%= plan_interval(@plan) %>  # => "month" or "3 months"
  def plan_interval(plan)
    if plan.interval_count > 1
      pluralize(plan.interval_count, plan.interval)
    else
      plan.interval
    end
  end
  
  # ==================== SUBSCRIPTION HELPERS ====================
  
  # Add more payment-related helpers here as needed:
  # - Subscription status badges
  # - Payment method formatting
  # - Currency formatting wrappers
  # - Trial period calculations
  # - Invoice helpers
end

