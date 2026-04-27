module Profile
  class PasswordsController < ApplicationController
    before_action :authenticate_user!

    def show
      redirect_to edit_profile_password_path
    end

    def edit
    end

    def update
      if current_user.update_with_password(password_params)
        bypass_sign_in(current_user)
        redirect_to(profile_password_path, notice: "Password updated successfully")
      else
        render(:edit, status: :unprocessable_content)
      end
    end

    private

    def password_params
      password_keys = [:current_password, :password, :password_confirmation]
      params.expect(user: password_keys)
    end
  end
end
