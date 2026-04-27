class PagesController < ApplicationController
  # This controller serves public, static ERB pages
  skip_before_action :authenticate_user!

  def index
    # ERB homepage - no build step, fast and reliable
    ahoy.track "Ran action", request.path_parameters if ENV['AHOY_TRACKING_ENABLED'] == 'true'
  end

  def privacy
  end

  def terms
  end

  def pricing
    unless RubyOnVibes.config.stripe? && plans.any?
      flash[:alert] = "Subscription are not enabled. Please contact support."
      redirect_to root_path
      return
    end

    # Group plans by interval
    grouped_plans = plans.group_by(&:interval)
    
    # Get available intervals in order (day, week, month, year)
    interval_order = ['month', 'year']
    @available_intervals = interval_order.select { |i| grouped_plans.key?(i) }
    
    # Set initial interval from query param or default to first available
    @initial_interval = params[:interval].presence_in(@available_intervals) || @available_intervals.first
    
    # Serialize plans for IslandJS component
    @plans_data = plans.map do |plan|
      {
        id: plan.prefix_id,
        name: plan.name,
        amount: plan.amount,
        currency: plan.currency,
        interval: plan.interval,
        interval_count: plan.interval_count || 1,
        description: plan.description,
        features: plan.features || [],
        contact_url: plan.contact_url,
        unit_label: plan.unit_label,
        trial_period_days: plan.trial_period_days || 0,
        trial_period: plan.trial_period?,
        checkout_path: plan.contact_url.present? ? nil : checkout_path(plan_id: plan.prefix_id)
      }
    end
    
    @grouped_plans_data = @plans_data.group_by { |p| p[:interval] }
  end

  def plans
    @plans ||= Plan.visible.sorted
  end
end