class Authentication::RegistrationsController < Devise::RegistrationsController
  include Authentication::Concerns::RegistrationHelpers

  before_action :configure_sign_up_params, only: [:create]
  before_action :copy_password_to_confirmation, only: [:create]

  def create
    super do
      refer resource if resource.persisted?
    end
  end

  protected

  def configure_sign_up_params
    devise_parameter_sanitizer.permit(:sign_up, keys: [:full_name])
  end

  def copy_password_to_confirmation
    if params[:user][:password].present? && params[:user][:password_confirmation].blank?
      params[:user][:password_confirmation] = params[:user][:password]
    end
  end

  def after_sign_up_path_for(resource)
    root_path
  end

  def build_resource(hash = {})
    self.resource = resource_class.new_with_session(hash, session)

    @invitation = Invitation.find_by(token: params[:invite]) if params[:invite].present?

    # Registering to accept an invitation should display the invitation on sign up
    if @invitation && !User.exists?(email: @invitation.email)
      resource.full_name ||= @invitation.name
      resource.email = resource.email.presence || @invitation.email
    else
      @invitation = nil # ensure we don't render invitation data publicly for existing users
    end
  end

  def update_resource(resource, params)
    # Allow user to edit their profile without requiring password re-entry
    resource.update_without_password(params)
  end

  def sign_up(resource_name, resource)
    super

    refer(resource) if defined?(Refer)

    if @invitation
      # Remove any default team workspaces to make the invited workspace the default.
      current_user.workspaces.where(is_team_workspace: true).destroy_all
      @invitation.accept!(current_user)

      # Clear redirect to workspace invitation since it's already been accepted
      stored_location_for(:user)
    end
  end
end