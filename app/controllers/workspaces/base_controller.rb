class Workspaces::BaseController < ApplicationController
  private

  ##
  # Override Pundit error handler to redirect to workspace instead of root.
  # This provides better UX - user stays in context of the workspace they were viewing.
  #
  def user_not_authorized(exception = nil)
    message = t("pundit.not_authorized", default: "You are not authorized to perform this action.")

    respond_to do |format|
      format.html do
        flash[:alert] = message
        redirect_to @workspace || workspaces_path
      end
      format.turbo_stream { head :forbidden }
      format.json { render json: { error: message }, status: :forbidden }
    end
  end
end
