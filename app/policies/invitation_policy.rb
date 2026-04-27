# frozen_string_literal: true

##
# InvitationPolicy - Authorization for workspace invitation actions
#
# Two contexts:
# 1. Top-level invitee actions (/invitations/:id) - invitee viewing/accepting/rejecting
# 2. Workspace-scoped admin actions (/workspaces/:workspace_id/invitations) - admins managing invitations
#
# Permissions:
# - Invitee: Can view, accept, or reject their own invitation
# - Workspace Admin: Can create, edit, resend, or cancel invitations
#
class InvitationPolicy < ApplicationPolicy
  # ============================================================================
  # Invitee Actions (top-level /invitations/:id)
  # ============================================================================

  ##
  # Only the invitee can view their invitation.
  #
  def show?
    invitee?
  end

  ##
  # Only the invitee can accept their invitation.
  # Maps to InvitationsController#update
  #
  def accept?
    invitee?
  end

  ##
  # Only the invitee can reject/decline their invitation.
  # Maps to InvitationsController#destroy
  #
  def reject?
    invitee?
  end

  # ============================================================================
  # Workspace Admin Actions (/workspaces/:workspace_id/invitations)
  # ============================================================================

  def index?
    workspace_admin?
  end

  def new?
    workspace_admin?
  end

  def create?
    workspace_admin?
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

  def resend?
    workspace_admin?
  end

  ##
  # Expose permissions as a hash for frontend consumption.
  #
  def to_h
    {
      "can_view" => show?,
      "can_accept" => accept?,
      "can_reject" => reject?,
      "can_manage" => workspace_admin?,
      "is_invitee" => invitee?
    }
  end

  private

  ##
  # Check if the current user is the invitation recipient.
  #
  def invitee?
    user.present? && user.email == record.email
  end

  ##
  # Check if the current user is an admin of the invitation's workspace.
  #
  def workspace_admin?
    return false unless user && record.workspace

    record.workspace.members.find_by(user: user)&.admin?
  end
end
