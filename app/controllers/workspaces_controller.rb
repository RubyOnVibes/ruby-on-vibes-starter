class WorkspacesController < Workspaces::BaseController
  before_action :authenticate_user!
  before_action :set_workspace, only: [:show, :edit, :update, :destroy, :start_session]
  before_action :prevent_personal_workspace_deletion, only: [:destroy]
  before_action :ensure_teams_enabled, except: [:index, :show]

  def index
    @pagy, @workspaces = pagy(current_user.workspaces)
  end

  def show
    authorize @workspace
  end

  def new
    return redirect_to workspaces_path, flash: { notice: "Team workspaces are not supported" } unless RubyOnVibes.teams?

    @workspace = Workspace.new
  end

  def edit
    authorize @workspace
  end

  def create
    return redirect_to workspaces_path, flash: { notice: "Team workspaces are not supported" } unless RubyOnVibes.teams?

    @workspace = Workspace.new(workspace_params.merge(owner: current_user))

    if @workspace.save
      flash[:notice] = "Workspace created successfully"
      start_session # to the new workspace
    else
      render :new, status: :unprocessable_content
    end
  end

  def update
    authorize @workspace

    if @workspace.update(workspace_params)
      redirect_to @workspace, notice: "Workspace updated successfully"
    else
      render :edit, status: :unprocessable_content
    end
  end

  def destroy
    authorize @workspace

    if @workspace.destroy
      redirect_to workspaces_url, status: :see_other, notice: "Workspace deleted successfully"
    else
      redirect_to @workspace, alert: "Failed to delete workspace"
    end
  end

  def start_session
    session[:workspace_id] = @workspace.id

    redirect_to url_from(params[:return_to]) || workspaces_path
  end

  private

  def set_workspace
    @workspace = current_user.workspaces.find_by_prefix_id!(params[:id])
  rescue ActiveRecord::RecordNotFound
    redirect_to workspaces_path
  end

  def workspace_params
    params.expect(workspace: [:avatar, :name])
  end

  def prevent_personal_workspace_deletion
    if @workspace.personal?
      redirect_to workspace_path(@workspace), alert: "Personal workspaces cannot be deleted"
    end
  end

  def ensure_teams_enabled
    redirect_to workspaces_path unless RubyOnVibes.config.teams?
  end
end
