class Madmin::User::SessionsController < Madmin::ApplicationController
  def create
    other_user = ::User.find(params[:user_id])
    impersonate_user(other_user)

    redirect_to main_app.root_path, status: :see_other
  end

  def destroy
    other_user = current_user
    stop_impersonating_user

    redirect_to main_app.madmin_user_path(other_user), status: :see_other
  end
end