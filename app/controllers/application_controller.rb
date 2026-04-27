class ApplicationController < ActionController::Base
  set_referral_cookie
  # Only allow modern browsers supporting webp images, web push, badges, import maps, CSS nesting, and CSS :has.
  allow_browser versions: :modern

  impersonates :user

  include CurrentRequestHelpers
  include Pagy::Method
  include Pundit::Authorization

  rescue_from Pundit::NotAuthorizedError, with: :user_not_authorized

  # NOTICE: We authenticate all actions by default.
  #
  # If you must use a different authentication strategy for a part of the app, you can skip this callback by adding `skip_before_action :authenticate_user!` to the controller where you want to skip authentication.
  # Public actions must have this callback explicity skipped — we authenticate all other actions by default.
  #
  before_action :authenticate_user!

  # Share flash messages with Inertia pages
  inertia_share flash: -> { flash.to_hash }

  after_action :set_vibes_request_id

  def set_vibes_request_id
    response.set_header('X-Vibes-Request-ID', request.uuid) if request.uuid
  end

  def require_sign_up_or_current_user!
    unless user_signed_in?
      store_location_for(:user, request.fullpath)
      redirect_to new_user_registration_path, alert: "You must sign up or sign in to access this page"
    end
  end

  def require_agent_tasks_enabled!
    redirect_to root_path unless RubyOnVibes.agent_tasks?
  end

  def require_chat_enabled!
    redirect_to root_path unless RubyOnVibes.chat?
  end

  def require_current_workspace_admin!
    unless Current.member&.admin?
      redirect_to root_path, alert: t("must_be_an_admin")
    end
  end

  # ============================================================================
  # Subscription Checks
  # ============================================================================

  ##
  # Checks if the current workspace has an active subscription.
  # Uses Pay gem's subscription status with optional product name filtering.
  #
  # @param product [String] Pay product name to check (defaults to Pay.default_product_name)
  # @return [Boolean] true if workspace is subscribed
  def subscribed?(product: Pay.default_product_name)
    return false unless user_signed_in?

    billing = current_workspace&.payment_processor
    billing.present? && billing.subscribed?(name: product)
  end
  helper_method :subscribed?

  ##
  # Inverse of subscribed? for readability in conditionals.
  #
  # @param product [String] Pay product name to check
  # @return [Boolean] true if workspace is NOT subscribed
  def not_subscribed?(product: Pay.default_product_name)
    !subscribed?(product: product)
  end
  helper_method :not_subscribed?

  ##
  # Before action to enforce subscription requirement.
  # Redirects to pricing page with a message if not subscribed.
  def require_subscription!
    return if subscribed?

    redirect_to pricing_path, alert: t("subscriptions.required", default: "A subscription is required to access this feature.")
  end

  private

  ##
  # Handle Pundit authorization failures with a consistent user experience.
  # For HTML: Redirects back or to root with an alert message.
  # For JSON/Turbo Stream: Returns appropriate error response.
  def user_not_authorized(exception = nil)
    message = t("pundit.not_authorized", default: "You are not authorized to perform this action.")

    respond_to do |format|
      format.html do
        flash[:alert] = message
        redirect_back(fallback_location: root_path)
      end
      format.turbo_stream { head :forbidden }
      format.json { render json: { error: message }, status: :forbidden }
    end
  end
end