# frozen_string_literal: true

##
# AgentTasksController - Workspace-level agent task views
#
# Provides the HTML index (paginated) and show views for agent tasks.
# Each task links back to its chat. The show page is a "run report"
# showing status, result, effects timeline, and raw data.
#
class AgentTasksController < ApplicationController
  before_action :authenticate_user!
  before_action :require_agent_tasks_enabled!
  include Pagy::Method

  # GET /agent_tasks
  def index
    scope = current_workspace.agent_tasks.order(created_at: :desc)

    if params[:status].present? && params[:status] != "all"
      scope = scope.where(status: AgentTask.statuses[params[:status]]) if AgentTask.statuses.key?(params[:status])
    end

    @pagy, @agent_tasks = pagy(scope, limit: 25)
    @status_counts = current_workspace.agent_tasks.group(:status).count
    @can_view_errors = current_member&.admin?
  end

  # GET /agent_tasks/:id
  def show
    @agent_task = current_workspace.agent_tasks.find_by_prefix_id!(params[:id])
    @effects = @agent_task.effects.by_recency
    @can_view_errors = current_member&.admin?
  end
end
