class Payments::Checkout::ReturnsController < ApplicationController
  before_action :authenticate_user!
  before_action :require_current_workspace_admin!

  def show
    object = Pay.sync(params)

    if object.is_a?(Pay::Charge)
      flash[:notice] = "Successfully charged"
    elsif object.is_a?(Pay::Subscription) && object.active?
      flash[:notice] = "Successfully subscribed"
    else
      flash[:alert] = "Bad request: contact support if this problem persists."
    end

    redirect_to url_from(params[:return_to]) || root_path
  end
end
