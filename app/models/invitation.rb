# frozen_string_literal: true

##
# Represents a pending invitation to join a workspace.
#
# Invitations can be sent to both existing users (in-app notification)
# and new users (email). When accepted, creates a Member record with
# the roles specified on the invitation.
#
# @example Creating and sending an invitation
#   invitation = Invitation.create!(
#     name: "John Doe",
#     email: "john@example.com",
#     workspace: workspace,
#     originator: current_user,
#     member: true
#   )
#   invitation.deliver
#
class Invitation < ApplicationRecord
  has_prefix_id :invite

  include Workspace::Roles

  has_secure_token

  belongs_to :originator, class_name: "User"
  belongs_to :workspace

  normalizes :email, with: ->(email) { email.strip.downcase }

  validates :name, presence: true
  validates :email, presence: true,
    uniqueness: { scope: :workspace_id, message: :already_invited },
    format: { with: URI::MailTo::EMAIL_REGEXP }

  def to_param
    token
  end

  ##
  # Reject/decline the invitation, removing it from the system.
  #
  # @return [Invitation] the destroyed invitation
  def reject!
    destroy
  end

  ##
  # Delivers the invitation to the invitee.
  #
  # For existing users: sends an in-app notification via Noticed.
  # For new users: sends an email invitation.
  #
  # @return [Boolean] true if delivery was initiated
  def deliver
    existing_user = User.find_by(email: email)

    if existing_user
      deliver_to_existing_user(existing_user)
    else
      deliver_to_new_user
    end

    true
  end

  private

  def deliver_to_existing_user(user)
    # Deliver in-app notification via Noticed
    # Store denormalized names so notification persists after invitation is deleted
    InvitationNotifier.with(
      invitation: self,
      originator_name: originator.name,
      workspace_name: workspace.name
    ).deliver(user)
  end

  def deliver_to_new_user
    InvitationsMailer.with(invitation: self).invite_email.deliver_later
  end

  public

  def accept!(user)
    raise "Email does not match" unless user.email == email

    member = nil

    ApplicationRecord.transaction do
      member = workspace.members.create!(user: user, roles: roles)
      destroy!
    end
      
    # Store denormalized names so notification persists after workspace deletion
    accepted_params = {
      workspace: workspace,
      record: user,
      user_name: user.name,
      workspace_name: workspace.name
    }
    InvitationAcceptedNotifier.with(accepted_params).deliver(originator) if originator.present?
    InvitationAcceptedNotifier.with(accepted_params).deliver(workspace.owner) if workspace.owner.present? && workspace.owner != originator

    member
  rescue ActiveRecord::ActiveRecordError => e
    errors.add(:base, e.message)
    nil
  end
end