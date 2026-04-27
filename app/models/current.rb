# frozen_string_literal: true

##
# Thread-safe global context for the current request.
#
# Provides access to the authenticated user, active workspace, and request metadata.
# Use sparingly - only for truly global concerns that span the entire request lifecycle.
#
# @example Setting context in a controller
#   Current.user = current_user
#   Current.workspace = workspace_from_session
#
# @example Checking permissions
#   Current.admin?              # => true if member has admin role
#   Current.workspace_owner?    # => true if user owns the workspace
#   Current.can_manage_workspace? # => true if owner OR admin
#
class Current < ActiveSupport::CurrentAttributes
  attribute :user, :workspace, :request_id, :ip_address, :user_agent

  resets { reset_time_zone }

  # Sets the current user and applies their time zone preference.
  def user=(value)
    super
    apply_user_time_zone(value)
    value
  end

  # Sets the current workspace and invalidates cached associations.
  def workspace=(value)
    super
    invalidate_workspace_cache
    value
  end

  # Returns the Member record linking current user to current workspace.
  # Memoized for the duration of the request.
  #
  # @return [Member, nil] the membership record, or nil if not a member
  def member
    return @member if defined?(@member)
    return nil unless user && workspace

    @member = workspace.members.includes(:user).find_by(user_id: user.id)
  end

  # Returns the user's active roles in the current workspace.
  #
  # @return [Array<Symbol>] list of active role names
  def roles
    return [] unless member

    member.active_roles.presence || []
  end

  # Checks if the current member has admin privileges.
  #
  # @return [Boolean]
  def admin?
    member&.admin? || false
  end

  # Checks if the current user owns the workspace.
  #
  # @return [Boolean]
  def workspace_owner?
    return false unless user && workspace

    workspace.owner_id == user.id
  end

  # Checks if the current user can manage workspace settings.
  # True for workspace owners and members with admin role.
  #
  # @return [Boolean]
  def can_manage_workspace?
    workspace_owner? || admin?
  end

  # Returns other workspaces the user belongs to (excluding current).
  # Memoized for the duration of the request.
  #
  # @return [ActiveRecord::Relation<Workspace>]
  def other_workspaces
    return @other_workspaces if defined?(@other_workspaces)

    @other_workspaces = fetch_other_workspaces
  end

  private

  def apply_user_time_zone(user)
    zone = user&.time_zone
    Time.zone = zone.present? ? Time.find_zone(zone) : nil
  end

  def reset_time_zone
    Time.zone = nil
  end

  def invalidate_workspace_cache
    remove_instance_variable(:@member) if defined?(@member)
    remove_instance_variable(:@other_workspaces) if defined?(@other_workspaces)
  end

  def fetch_other_workspaces
    return Workspace.none unless user

    user.workspaces.where.not(id: workspace&.id).order(:id)
  end
end 