# frozen_string_literal: true

module Api
  module V1
    ##
    # AgentTasksController - JSON API for agent task polling and management
    #
    # The frontend AgentTaskPanel polls these endpoints to track
    # background task progress. Tasks run in SolidQueue/Sidekiq
    # (separate process) and update the DB — this controller reads
    # that state for the client.
    #
    # GET /api/v1/agent_tasks?chat_id=chat_xxx       — list tasks for a chat
    # GET /api/v1/agent_tasks/:id                     — single task status
    # POST /api/v1/agent_tasks/:id/cancel             — cancel a task
    # POST /api/v1/agent_tasks/dismiss?chat_id=xxx    — dismiss terminal tasks from view
    #
    class AgentTasksController < Api::V1::BaseController
      before_action :authenticate_user!
      before_action :require_agent_tasks_enabled!
      before_action :set_agent_task, only: [:show, :cancel]

      # GET /api/v1/agent_tasks?chat_id=chat_xxx&status=active
      def index
        return render json: { error: "chat_id is required" }, status: :bad_request if params[:chat_id].blank?

        chat = current_member.chats.find_by_prefix_id(params[:chat_id])
        return render json: { error: "Chat not found" }, status: :not_found unless chat

        scope = chat.agent_tasks.order(created_at: :desc)

        # Filter out dismissed terminal tasks (completed before the chat's dismissed_at timestamp)
        if chat.agent_tasks_dismissed_at.present?
          scope = scope.where("status IN (?, ?) OR completed_at > ? OR completed_at IS NULL",
            AgentTask.statuses[:pending], AgentTask.statuses[:running],
            chat.agent_tasks_dismissed_at)
        end

        case params[:status]
        when "active"
          scope = scope.active
        when "completed"
          scope = scope.status_completed
        when "terminal"
          scope = scope.terminal
        end

        tasks = scope.limit(params[:limit]&.to_i || 50)

        render json: {
          tasks: tasks.map { |t| serialize_task(t) },
          has_active: chat.agent_tasks.active.exists?
        }
      end

      # GET /api/v1/agent_tasks/:id
      def show
        render json: serialize_task(@agent_task)
      end

      # POST /api/v1/agent_tasks/:id/cancel
      def cancel
        if @agent_task.active? && @agent_task.cancel!
          render json: { status: "cancelled" }, status: :ok
        else
          render json: { error: "Cannot cancel task (status: #{@agent_task.status})" }, status: :unprocessable_content
        end
      end

      # POST /api/v1/agent_tasks/dismiss?chat_id=chat_xxx
      # Sets a timestamp on the chat so terminal tasks completed before it are hidden.
      def dismiss
        return render json: { error: "chat_id is required" }, status: :bad_request if params[:chat_id].blank?

        chat = current_member.chats.find_by_prefix_id(params[:chat_id])
        return render json: { error: "Chat not found" }, status: :not_found unless chat

        chat.update!(agent_tasks_dismissed_at: Time.current)
        render json: { dismissed_at: chat.agent_tasks_dismissed_at.iso8601 }, status: :ok
      end

      private

      def require_agent_tasks_enabled!
        render json: { error: "Agent tasks are not enabled" }, status: :not_found unless RubyOnVibes.agent_tasks?
      end

      def set_agent_task
        @agent_task = current_workspace.agent_tasks.find_by_prefix_id(params[:id])
        render json: { error: "Task not found" }, status: :not_found unless @agent_task
      end

      def serialize_task(task)
        data = {
          id: task.to_param,
          kind: task.kind,
          status: task.status,
          progress: task.progress,
          progressText: task.progress_text,
          attempts: task.attempts,
          startedAt: task.started_at&.iso8601,
          completedAt: task.completed_at&.iso8601,
          createdAt: task.created_at.iso8601
        }

        data[:result] = task.result if task.status_completed? || task.status_awaiting_approval?

        if task.status_failed?
          data[:errorMessage] = admin_in_task_workspace?(task) ? task.error_message : "Task failed"
        end

        data
      end

      # Check if the current user is an admin in the task's workspace,
      # not just their current workspace (cross-workspace chat members
      # should only see error details if they're admin in the task's workspace).
      def admin_in_task_workspace?(task)
        member = task.workspace.members.find_by(user: current_user)
        member&.admin?
      end
    end
  end
end
