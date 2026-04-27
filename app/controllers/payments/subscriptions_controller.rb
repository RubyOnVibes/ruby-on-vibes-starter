class Payments::SubscriptionsController < ApplicationController
  before_action :require_current_workspace_admin!, except: [:index, :show]
  before_action :set_plan, only: [:update]
  before_action :set_subscription, only: [:show, :edit, :update, :cancelling, :cancel, :pausing, :pause, :unpausing, :unpause, :upcoming]

  def index
    redirect_to(payments_url)
  end

  def show
    redirect_to(edit_subscription_path(@subscription))
  end

  def edit
    load_relevant_plans
  end

  def update
    @subscription.swap(@plan.stripe_id)

    redirect_to payments_path, notice: "Plan changed successfully."
  rescue Pay::Error => e
    load_relevant_plans

    flash[:alert] = e.message
    render :edit, status: :unprocessable_content
  rescue Pay::ActionRequired => e
    redirect_to pay.payment_path(e.payment.id)
  end

  # Cancel subscription flow
  def cancelling
  end

  def cancel
    cancel_subscription
    redirect_to payments_path, status: :see_other
  rescue Pay::Error => e
    render :cancelling, status: :unprocessable_content, alert: e.message
  end

  # Pause subscription flow
  def pausing
  end

  def pause
    @subscription.pause
    redirect_to payments_path
  rescue Pay::Error => e
    render :pausing, status: :unprocessable_content, alert: e.message
  end

  # Resume/unpause subscription flow
  def unpausing
  end

  def unpause
    @subscription.resume
    redirect_to payments_path
  rescue Pay::Error => e
    render :unpausing, status: :unprocessable_content, alert: e.message
  end

  # View upcoming invoice
  def upcoming
    @invoice = @subscription.preview_invoice
  rescue Stripe::InvalidRequestError => e
    redirect_to payments_path, alert: e.message
  end

  # Payment method management
  def new_payment_method
    set_subscription

    if @subscription.customer.processor == "stripe"
      stripe_billing_portal_url = @subscription.customer.billing_portal(return_url: payments_url).url
      redirect_to(stripe_billing_portal_url, allow_other_host: true)
    else
      redirect_to "/payments", alert: "Payment processor not supported."
    end
  end

  private

  def set_plan
    @plan = Plan.find_by_prefix_id!(params[:plan_id]) # load any plan by prefix_id (even hidden ones)
  rescue ActiveRecord::RecordNotFound
    redirect_to pricing_path
  end

  def set_subscription
    @subscription = current_workspace.pay_subscriptions.find_by_prefix_id!(params[:id])
  rescue ActiveRecord::RecordNotFound
    redirect_to payments_path if @subscription.nil?
  end

  def load_relevant_plans
    @current_plan = @subscription.plan
    plans = Plan.where(id: @current_plan.id).or(Plan.visible).order(created_at: :desc)
    @monthly_plans, @yearly_plans = plans.partition(&:monthly?)
  end

  def cancel_subscription
    if @subscription.metered?
      @subscription.cancel_now!(invoice_now: true)
    elsif @subscription.unpaid? || @subscription.past_due?
      @subscription.cancel_now!
    else # cancels at period end (default pay behavior)
      @subscription.cancel
    end
  end
end
