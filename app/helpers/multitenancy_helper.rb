module MultitenancyHelper
  # Multi-tenant Workspace Management
  #
  # Provides view helpers for workspace display, member role presentation,
  # and workspace switching in multi-tenant applications.

  # ============================================================================
  # Member Role Display
  # ============================================================================

  ##
  # Returns human-readable role labels for a workspace member.
  #
  # Includes ownership status and all active roles from Workspace::Roles.
  # Useful for displaying member badges or permission summaries.
  #
  # @param workspace [Workspace] the workspace context
  # @param member [Member] the member to get roles for
  # @return [Array<String>] list of role labels (e.g., ["Owner", "Admin"])
  #
  # @example Display roles as badges
  #   <% member_role_labels(@workspace, @member).each do |label| %>
  #     <span class="badge"><%= label %></span>
  #   <% end %>
  #
  def member_role_labels(workspace, member)
    labels = []

    # Check ownership first (special status, not a role)
    if owns_workspace?(workspace, member)
      labels << "Owner"
    end

    # Add active roles from the roles system
    member.active_roles.each do |role|
      labels << role.to_s.titleize
    end

    labels
  end

  ##
  # Checks if a user has admin privileges in a workspace.
  #
  # @param workspace [Workspace] the workspace to check
  # @param user [User] the user to check
  # @return [Boolean] true if user is an admin in the workspace
  #
  def workspace_admin?(workspace, user)
    workspace.members.find_by(user: user)&.admin? || false
  end

  # ============================================================================
  # Workspace Navigation
  # ============================================================================

  ##
  # Renders a button to switch the active workspace session.
  #
  # Only shown when teams feature is enabled. Uses PATCH request
  # to update session-based workspace context.
  #
  # @param workspace [Workspace] the workspace to switch to
  # @param label [String] button text (defaults to workspace name)
  # @param return_to [String, nil] path to redirect after switching
  # @param form_class [String, nil] CSS class for the form wrapper
  # @return [String, nil] HTML button_to tag, or nil if teams disabled
  #
  def enter_workspace_button(workspace, label: workspace.name, return_to: nil, form_class: nil, **html_options)
    return unless RubyOnVibes.config.teams?

    switch_path = start_session_workspace_path(workspace.prefix_id, return_to: return_to)

    form_opts = { method: :patch }
    form_opts[:form] = { class: form_class } if form_class

    button_to(label, switch_path, **html_options.merge(form_opts))
  end

  private

  # Resolves the appropriate avatar source for a workspace
  def resolve_workspace_avatar_src(workspace, pixel_size)
    # Personal workspace shows the owner's (current user's) avatar
    if workspace.personal? && workspace.owner_id == current_user&.id
      return avatar_url(current_user, size: pixel_size)
    end

    # Team workspace with uploaded avatar
    if workspace.avatar.attached? && workspace.avatar.variable?
      return workspace.avatar.variant(resize_to_fit: [pixel_size, pixel_size])
    end

    # Fallback to initials-based avatar
    ui_avatar_url(name: workspace.name, size: pixel_size)
  end

  # Checks if a member owns the workspace
  def owns_workspace?(workspace, member)
    return false unless member.respond_to?(:user_id)

    workspace.owner_id == member.user_id
  end
end

