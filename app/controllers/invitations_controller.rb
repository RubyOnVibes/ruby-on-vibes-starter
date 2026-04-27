class InvitationsController < ApplicationController
  skip_before_action :authenticate_user!, only: [:show]
  before_action :set_invitation
  before_action :redirect_with_invite_link_stored_maybe!

  def show
    authorize @invitation
  end

  def update
    authorize @invitation, :accept?

    if @invitation.accept!(current_user)
      redirect_to workspaces_path
    else
      redirect_to invitation_path(@invitation), alert: @invitation.errors.full_messages.first || "Something went wrong"
    end
  end

  def destroy
    authorize @invitation, :reject?

    if @invitation.destroy
      redirect_to root_path, status: :see_other
    else
      redirect_to @invitation, alert: @invitation.errors.full_messages.first
    end
  end

  private

  def set_invitation
    @invitation = Invitation.find_by!(token: params[:id])
  rescue ActiveRecord::RecordNotFound
    redirect_to root_path, alert: "Invitation not found"
  end

  def redirect_with_invite_link_stored_maybe!
    if current_user.nil? && !User.exists?(email: @invitation.email)
      store_location_for(:user, request.fullpath)
      redirect_to new_user_registration_path(invite: @invitation.token), alert: "You must sign up or sign in to access this page"
    end
  end
end