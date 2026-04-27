class InvitationsMailer < ApplicationMailer
  # Workspace invitation email
  #
  # Sends a branded invitation email to join a workspace. Supports both
  # new user signups and existing user notifications.
  #
  # Required params:
  #   - invitation: The Invitation record
  #
  #
  def invite_email
    @invitation = params[:invitation]

    setup_invitation_context

    mail(
      to: recipient_address,
      from: sender_address,
      subject: invitation_subject,
      reply_to: inviter_reply_to
    )
  end

  private

  def setup_invitation_context
    @workspace = @invitation.workspace
    @inviter = @invitation.originator
    @inviter_name = @inviter&.name.presence || "A team member"
    @accept_url = invitation_url(@invitation)
    @app_name = RubyOnVibes.application_name
  end

  def recipient_address
    email_address_with_name(@invitation.email, @invitation.name)
  end

  def sender_address
    email_address_with_name(
      RubyOnVibes.config.support_email,
      "#{@app_name} Invitations"
    )
  end

  # Allow replies to go to the person who sent the invite
  def inviter_reply_to
    return nil unless @inviter&.email.present?

    email_address_with_name(@inviter.email, @inviter_name)
  end

  def invitation_subject
    "Join #{@workspace.name} on #{@app_name}"
  end
end