class Workspaces::InvitationsController < Workspaces::BaseController
  # Manages workspace team invitations
  #
  # Invitations go through a lifecycle:
  #   1. Created by admin with name, email, roles
  #   2. Delivered via email (new users) or in-app notification (existing users)
  #   3. Accepted or rejected by invitee
  #
  # Only workspace admins can manage invitations (enforced via Pundit).

  before_action :authenticate_user!
  before_action :load_workspace
  before_action :load_invitation, only: [:edit, :update, :destroy, :resend]

  # GET /workspaces/:workspace_id/invitations/new
  def new
    @invitation = build_invitation
    authorize @invitation
  end

  # POST /workspaces/:workspace_id/invitations
  def create
    @invitation = build_invitation(invitation_params)
    authorize @invitation

    if save_and_deliver_invitation
      redirect_with_success("Invitation sent to #{@invitation.email}")
    else
      render :new, status: :unprocessable_content
    end
  end

  # GET /workspaces/:workspace_id/invitations/:id/edit
  def edit
    authorize @invitation
  end

  # PATCH /workspaces/:workspace_id/invitations/:id
  def update
    authorize @invitation

    if @invitation.update(invitation_params)
      redirect_with_success("Invitation updated")
    else
      render :edit, status: :unprocessable_content
    end
  end

  # DELETE /workspaces/:workspace_id/invitations/:id
  def destroy
    authorize @invitation

    @invitation.destroy
    redirect_with_success("Invitation cancelled", status: :see_other)
  end

  # POST /workspaces/:workspace_id/invitations/:id/resend
  def resend
    authorize @invitation

    @invitation.deliver
    redirect_with_success("Invitation resent to #{@invitation.email}", status: :see_other)
  end

  private

  # ============================================================================
  # Resource Loading
  # ============================================================================

  def load_workspace
    @workspace = current_user.workspaces.find_by_prefix_id!(params[:workspace_id])
  rescue ActiveRecord::RecordNotFound
    redirect_to workspaces_path, alert: "Workspace not found" and return
  end

  def load_invitation
    @invitation = @workspace.invitations.find_by!(token: params[:id])
  rescue ActiveRecord::RecordNotFound
    redirect_to @workspace, alert: "Invitation not found or already accepted" and return
  end

  # ============================================================================
  # Invitation Building
  # ============================================================================

  def build_invitation(attrs = {})
    @workspace.invitations.new(attrs).tap do |inv|
      inv.originator = current_user
    end
  end

  def save_and_deliver_invitation
    return false unless @invitation.save

    @invitation.deliver
    true
  end

  # ============================================================================
  # Parameters
  # ============================================================================

  def invitation_params
    permitted = params.require(:invitation).permit(:name, :email, *Member::ROLES)
    permitted
  end

  # ============================================================================
  # Response Helpers
  # ============================================================================

  def redirect_with_success(message, status: nil)
    redirect_options = { notice: message }
    redirect_options[:status] = status if status
    redirect_to @workspace, **redirect_options
  end
end
