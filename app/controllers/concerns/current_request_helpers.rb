# frozen_string_literal: true

##
# Sets up the request context for multi-tenant workspace access.
#
# This concern populates Current attributes with user, workspace, and request
# metadata. Workspace resolution follows a priority chain: params > session > default.
#
# @example Include in ApplicationController
#   class ApplicationController < ActionController::Base
#     include CurrentRequestHelpers
#   end
#
module CurrentRequestHelpers
  extend ActiveSupport::Concern

  included do |base|
    next unless base < ActionController::Metal

    set_current_tenant_through_filter if defined?(ActsAsTenant)
    before_action :setup_current

    helper_method :current_workspace, :current_member
  end

  # ============================================================================
  # Public Accessors
  # ============================================================================

  ##
  # Returns the currently active workspace for this request.
  #
  # @return [Workspace, nil]
  def current_workspace
    Current.workspace
  end

  ##
  # Returns the current user's membership in the active workspace.
  #
  # @return [Member, nil]
  def current_member
    Current.member
  end

  # ============================================================================
  # Context Setup
  # ============================================================================

  ##
  # Populates Current attributes with request context.
  # Called automatically via before_action.
  #
  def setup_current
    populate_request_metadata
    populate_user_workspace_context
  end

  # ============================================================================
  # Workspace Resolution Chain
  # ============================================================================

  ##
  # Resolves the workspace using the priority chain.
  # Order: params > session > default
  #
  # @return [Workspace, nil]
  def resolve_workspace
    return nil unless user_signed_in?

    resolve_workspace_from_params ||
      resolve_workspace_from_session ||
      default_workspace
  end

  ##
  # Attempts to resolve workspace from request params.
  #
  # @return [Workspace, nil]
  def resolve_workspace_from_params
    workspace_id = params[:workspace_id]
    return nil if workspace_id.blank?

    find_user_workspace(workspace_id)
  end

  ##
  # Attempts to resolve workspace from session.
  #
  # @return [Workspace, nil]
  def resolve_workspace_from_session
    workspace_id = session[:workspace_id]
    return nil if workspace_id.blank?

    find_user_workspace(workspace_id)
  end

  ##
  # Returns the default workspace (personal workspace).
  # Creates one if it doesn't exist.
  #
  # @return [Workspace]
  def default_workspace
    current_user&.personal_workspace || current_user&.create_personal_workspace
  end

  private

  # ============================================================================
  # Private Helpers
  # ============================================================================

  def populate_request_metadata
    Current.request_id = request.uuid
    Current.ip_address = request.ip
    Current.user_agent = request.user_agent
  end

  def populate_user_workspace_context
    Current.user = current_user
    Current.workspace ||= resolve_workspace
    configure_tenant if Current.workspace
  end

  def configure_tenant
    return unless defined?(ActsAsTenant) && respond_to?(:set_current_tenant, true)

    set_current_tenant(Current.workspace)
  end

  ##
  # Finds a workspace belonging to the current user.
  # Eager loads associations needed for billing/display.
  #
  # @param workspace_id [Integer, String] the workspace ID to find
  # @return [Workspace, nil]
  def find_user_workspace(workspace_id)
    return nil unless user_signed_in?

    current_user.workspaces
      .includes(:owner)
      .find_by(id: workspace_id)
  end
end
