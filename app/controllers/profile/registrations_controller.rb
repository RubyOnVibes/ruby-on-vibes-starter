module Profile
  class RegistrationsController < ApplicationController
    before_action :authenticate_user!

    def edit
    end

    def update
      if current_user.update(user_params)
        # If email changed and confirmable is enabled, Devise handles confirmation automatically
        if current_user.unconfirmed_email.present?
          redirect_to edit_profile_registration_path, notice: "Profile updated. Please check your email to confirm your new address."
        else
          redirect_to edit_profile_registration_path, notice: "Profile updated successfully."
        end
      else
        render :edit, status: :unprocessable_content
      end
    end

    private

    def user_params
      params.require(:user).permit(
        :username,
        :avatar,
        :first_name,
        :last_name,
        :email,
        :time_zone
      )
    end
  end
end
