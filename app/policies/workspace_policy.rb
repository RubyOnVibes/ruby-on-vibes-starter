# frozen_string_literal: true

##
# WorkspacePolicy - Authorization for workspace actions
#
# Permissions:
# - Show: Any workspace member
# - Edit/Update/Destroy: Workspace admins only
#
class WorkspacePolicy < ApplicationPolicy
  def show?
    workspace_member?
  end

  def edit?
    workspace_admin?
  end

  def update?
    workspace_admin?
  end

  def destroy?
    workspace_admin?
  end

  ##
  # Expose permissions as a hash for frontend consumption.
  #
  def to_h
    {
      "can_view" => show?,
      "can_edit" => edit?,
      "can_destroy" => destroy?,
      "is_admin" => workspace_admin?,
      "is_member" => workspace_member?
    }
  end

  private

  def workspace_member?
    return false unless user

    record.members.exists?(user: user)
  end

  def workspace_admin?
    return false unless user

    record.members.find_by(user: user)&.admin?
  end
end
