class Payments::CheckoutController < ApplicationController
  before_action :require_sign_up_or_current_user!
  before_action :require_current_workspace_admin!
  before_action :set_plan
  before_action :redirect_if_already_subscribed!, only: [:show]
  before_action :redirect_if_past_due_or_unpaid!, only: [:show]

  def show
    if RubyOnVibes.config.stripe?
      set_stripe_checkout_session
    else
      flash[:alert] = "No payment processor configured. Please contact support."
      redirect_to pricing_path
    end
  rescue Pay::Error => e
    redirect_to pricing_path, alert: e.message
  end

  private

  def set_plan
    @plan = Plan.find_by_prefix_id!(params[:plan_id])
  rescue ActiveRecord::RecordNotFound
    redirect_to pricing_path
  end

  def redirect_if_already_subscribed!
    if current_workspace.payment_processor&.subscribed?
      redirect_to payments_path, alert: "You are already subscribed."
    end
  end

  def redirect_if_past_due_or_unpaid!
    if (subscription = current_workspace.payment_processor&.subscription) && (subscription.past_due? || subscription.unpaid?)
      redirect_to payments_path, alert: "Your subscription is #{ (subscription.past_due? ? "past due" : "unpaid") }."
    end
  end

  def not_previously_subscribed?
    current_workspace.pay_subscriptions.none?
  end

  def trial_period_days
    if @plan.trial_period_days.to_i > 1 && not_previously_subscribed?
      @plan.trial_period_days
    else
      nil
    end
  end

  def metadata_params
    params.fetch(:metadata, {}).permit! # brakeman:ignore MassAssignment
  end

  def subscription_data
    {
      trial_settings: { end_behavior: { missing_payment_method: "pause" } },
      trial_period_days: trial_period_days,
      metadata: metadata_params.to_h,
    }.compact
  end

  def set_stripe_checkout_session
    # Set up embedded checkout session
    checkout_arguments = {
      ui_mode:                   :embedded,
      allow_promotion_codes:     true,
      subscription_data:         subscription_data,
      mode:                      :subscription,
      line_items:                @plan.stripe_id,
      automatic_tax:             { enabled: @plan.taxed? },
      consent_collection:        { terms_of_service: :required },
      customer_update:           { address: :auto },
      return_url:                checkout_return_url(return_to: params[:return_to]),
      payment_method_collection: :if_required
    }

    if @plan.charge_per_unit?
      checkout_arguments[:quantity] = current_workspace.per_unit_quantity
    end

    @checkout_session = current_workspace.
      set_payment_processor(:stripe).
      checkout(**checkout_arguments)
  end
end