class PaymentsController < ApplicationController
  before_action :authenticate_user!
  before_action :require_current_workspace_admin!, except: [:show]

  def show
    @payment_processor = current_workspace.payment_processor
    @subscriptions = current_workspace.pay_subscriptions.active.or(current_workspace.pay_subscriptions.past_due).or(current_workspace.pay_subscriptions.unpaid).order(created_at: :asc).includes([:customer])
  end

  def update
    current_workspace.update(billing_params)
    redirect_to payments_path, notice: "Update successful"
  end

  private

  def billing_params
    params.expect(workspace: [:extra_billing_info, :billing_email])
  end

  def set_subscription
    @subscription = current_workspace.pay_subscriptions.find_by_prefix_id!(params.fetch(:subscription_id))
  rescue ActiveRecord::RecordNotFound
    redirect_to payments_path
  end
end
