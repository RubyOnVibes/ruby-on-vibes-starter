# frozen_string_literal: true

##
# MemberPolicy - Authorization for member actions
#
# Permissions:
# - Show (top-level): Any authenticated user can view basic profile
# - Edit/Update/Destroy (workspace-scoped): Workspace admins only
# - Cannot destroy the workspace owner
#
class MemberPolicy < ApplicationPolicy
  # ============================================================================
  # Top-level Member Actions (/members/:id)
  # ============================================================================

  ##
  # Any authenticated user can view a member's profile.
  # The view layer can use `same_workspace?` to determine what details to show.
  #
  def show?
    user.present?
  end

  ##
  # Check if the viewer shares a workspace with the member.
  # Used by views to conditionally display information.
  #
  def same_workspace?
    return false unless user && record.workspace

    user.members.exists?(workspace_id: record.workspace_id)
  end

  # ============================================================================
  # Workspace-scoped Member Actions (/workspaces/:workspace_id/members/:id)
  # ============================================================================

  ##
  # Workspace members can view the member list.
  #
  def index?
    workspace_member?
  end

  ##
  # Only workspace admins can edit member roles.
  #
  def edit?
    workspace_admin?
  end

  def update?
    workspace_admin?
  end

  ##
  # Only workspace admins can remove members.
  # Additional check: cannot remove the workspace owner (enforced in policy).
  #
  def destroy?
    workspace_admin? && !record.workspace_owner?
  end

  ##
  # Expose permissions as a hash for frontend consumption.
  #
  def to_h
    {
      "can_view" => show?,
      "can_edit" => edit?,
      "can_destroy" => destroy?,
      "same_workspace" => same_workspace?,
      "is_workspace_admin" => workspace_admin?
    }
  end

  private

  def workspace_member?
    return false unless user && record.workspace

    record.workspace.members.exists?(user: user)
  end

  def workspace_admin?
    return false unless user && record.workspace

    record.workspace.members.find_by(user: user)&.admin?
  end
end
