# Nested member admin actions: /workspaces/:workspace_id/members/:id
# Authorization via Pundit MemberPolicy
module Workspaces
  class MembersController < Workspaces::BaseController
    before_action :authenticate_user!
    before_action :set_workspace
    before_action :require_non_personal_workspace!
    before_action :set_member, only: [:edit, :update, :destroy]

    def index
      authorize Member.new(workspace: @workspace), :index?
      redirect_to @workspace
    end

    def edit
      authorize @member
    end

    def update
      authorize @member

      if @member.update(member_params)
        redirect_to @workspace, notice: "Update successful"
      else
        render :edit, status: :unprocessable_content
      end
    end

    def destroy
      # Provide specific error message for attempting to remove workspace owner
      # Check this before authorize for a clearer user message
      if @member.workspace_owner?
        redirect_to @workspace, alert: "Cannot remove the workspace owner"
        return
      end

      authorize @member

      if @member.destroy
        redirect_to @workspace, status: :see_other, notice: "User removed from workspace"
      else
        redirect_to @workspace, status: :see_other, notice: "Failed to remove user"
      end
    end

    private

    def set_workspace
      @workspace = current_user.workspaces.find_by_prefix_id(params[:workspace_id])
      redirect_to workspaces_path if @workspace.blank?
    end

    def set_member
      @member = @workspace.members.find_by_prefix_id(params[:id])
      redirect_to @workspace if @member.blank?
    end

    def member_params
      params.expect(member: Member::ROLES)
    end

    def require_non_personal_workspace!
      redirect_to workspaces_path if @workspace.personal?
    end
  end
end
