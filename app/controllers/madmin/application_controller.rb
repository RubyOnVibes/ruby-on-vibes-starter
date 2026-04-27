module Madmin
  class ApplicationController < Madmin::BaseController
    before_action :authenticate_admin_user

    impersonates :user

    def refresh_models
      Model.refresh!
      redirect_to "/admin/models", notice: "LLMs refreshed successfully"
    end

    def authenticate_admin_user
      # For example, with Rails 8 authentication
      # redirect_to "/", alert: "Not authorized." unless authenticated? && Current.user.admin?

      # Or with Devise
      redirect_to "/", alert: "Not authorized." unless (true_user || current_user)&.admin?
    end
  end
end
