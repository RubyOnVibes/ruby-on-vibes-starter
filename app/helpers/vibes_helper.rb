# Helper for Vibes design system
# Single source of truth for design tokens used across web and email templates
module VibesHelper
  # Design tokens as Ruby hash - LIGHT MODE
  # SINGLE SOURCE OF TRUTH for all colors (web + email)
  # Edit these values to customize your brand colors
  # These are used by:
  #   - Web: _vibes_theme.html.erb (generates CSS variables)
  #   - Email: _vibes_email_theme.html.erb (generates inline styles)
  def vibes_tokens
    {
      # Surface colors (RGB triplets)
      surface_0: "252 252 253",
      surface_1: "248 250 252",
      surface_2: "241 245 249",
      surface_3: "226 232 240",
      
      # Text colors - text_2 is muted/secondary text (Slate 600 for better contrast)
      text_1: "15 23 42",
      text_2: "71 85 105",
      
      # Brand colors - CUSTOMIZE THESE for your brand
      brand: "30 64 175",  # Primary brand color
      brand_contrast: "255 255 255",
      accent: "238 242 255",
      secondary: "241 245 249",
      danger: "225 29 72",
      
      # Status colors
      info: "59 130 246",
      info_contrast: "255 255 255",
      warning: "245 158 11",
      warning_contrast: "15 23 42",
      success: "34 197 94",
      success_contrast: "255 255 255",

      # Chart colors (for data visualization)
      chart_1: "59 130 246",
      chart_2: "16 185 129",
      chart_3: "245 158 11",
      chart_4: "139 92 246",
      chart_5: "236 72 153"
    }
  end
  
  # Design tokens for dark mode
  # Customize dark mode appearance separately from light mode
  def vibes_tokens_dark
    {
      # NOTE: Status colors (info, warning, success + contrasts) are intentionally
      # omitted — saturated colors work well on dark backgrounds, so they inherit
      # light-mode values. Override here if a specific dark variant is needed.

      # Surface colors (darker)
      surface_0: "25 25 25",
      surface_1: "15 23 42",
      surface_2: "30 41 59",
      surface_3: "51 65 85",
      
      # Text colors (lighter for dark backgrounds - Slate 300 for better contrast)
      text_1: "226 232 240",
      text_2: "203 213 225",
      
      # Brand colors - often inverted for dark mode
      brand: "255 255 255",  # White brand in dark mode
      brand_contrast: "2 6 23",  # Dark text on white brand
      accent: "30 41 59",
      secondary: "30 41 59",
      danger: "244 63 94",

      # Chart colors (for data visualization — dark mode variants)
      chart_1: "96 165 250",
      chart_2: "52 211 153",
      chart_3: "251 191 36",
      chart_4: "167 139 250",
      chart_5: "244 114 182"
    }
  end
  
  # Check if we're rendering in a mailer context (no CSP nonces available)
  def in_mailer_context?
    !respond_to?(:content_security_policy_nonce)
  rescue
    true
  end
  
  # Safe nonce attribute - only renders in web context
  def safe_nonce_attr
    return "" if in_mailer_context?
    %( nonce="#{content_security_policy_nonce}")
  end

  def user_data_attrs
    return "null" unless current_user  # JSON null, not empty object (which is truthy in JS)
    
    { id: current_user.to_param,  # Use prefix_id for consistency
      username: current_user.username,
      email: current_user.email,
      firstName: current_user.first_name,
      lastName: current_user.last_name,
      timeZone: current_user.time_zone,
      admin: current_user.admin,
      avatarUrl: current_user.avatar.attached? ? url_for(current_user.avatar) : nil,
      # Multitenancy context
      currentWorkspace: current_workspace_attrs,
      currentMember: current_member_attrs }.to_json
  end

  def app_data_attrs
    { name: RubyOnVibes.application_name,
      businessName: RubyOnVibes.business_name,
      businessAddress: RubyOnVibes.business_address,
      supportEmail: RubyOnVibes.support_email,
      supportPhone: RubyOnVibes.support_phone,
      navItems: nav_menu_items,
      settingsNavItems: settings_nav_items }.to_json
  end

  # Navigation items for the user dropdown menu
  # Single source of truth: JS reads via window.App.data().navItems
  def nav_menu_items
    items = []
    items << { key: "chat", label: "Chat", path: "/chats", icon: "MessageSquare" } if RubyOnVibes.chat?
    items << { key: "workspaces", label: "Workspaces", path: "/workspaces", icon: "Workspace" } if RubyOnVibes.teams?
    items
  end

  # Settings navigation items - single source of truth
  # JS reads via window.App.data().settingsNavItems
  # Used by both ERB _sidebar_nav.html.erb and React SettingsSidebar component
  #
  # NOTE: Uses hardcoded paths as fallbacks to ensure nav always renders.
  # Route helpers may fail during asset compilation or early request lifecycle.
  def settings_nav_items
    items = []

    # Dashboard - always available when enabled (hardcoded path, no route helper needed)
    items << { key: "dashboard", label: "Dashboard", path: "/dashboard" } if dashboard_enabled?

    # Profile - core settings page
    items << { key: "profile", label: "Profile", path: profile_path_safe }

    # Chat - if LLM/chat is enabled
    items << { key: "chat", label: "Chat", path: "/chats", startsWithPath: "/chats" } if chat_enabled?

    # Agent Tasks - defaults to chat enabled, but independently overridable
    items << { key: "agent_tasks", label: "Agent Tasks", path: "/agent_tasks", startsWithPath: "/agent_tasks" } if agent_tasks_enabled?

    # Workspaces - if teams are enabled
    items << { key: "workspaces", label: "Workspaces", path: "/workspaces", startsWithPath: "/workspaces" } if teams_enabled?

    # Password - core settings page
    items << { key: "password", label: I18n.t("settings_navbar.password", default: "Password"), path: password_path_safe }

    # Payments - if Stripe is enabled
    items << { key: "payments", label: "Payments", path: "/payments", startsWithPath: "/payments" } if payments_enabled?

    # Referrals - if referrals gem and config are enabled
    items << { key: "referrals", label: "Referrals", path: "/profile/referrals" } if referrals_enabled?

    items
  end

  # Safe accessors for settings_nav_items - each handles its own errors

  def dashboard_enabled?
    RubyOnVibes.dashboard?
  rescue
    true  # Default to showing dashboard
  end

  def chat_enabled?
    RubyOnVibes.chat?
  rescue
    false
  end

  def teams_enabled?
    RubyOnVibes.teams?
  rescue
    false
  end

  def payments_enabled?
    RubyOnVibes.config.stripe? && !hotwire_native_app_safe?
  rescue
    false
  end

  def agent_tasks_enabled?
    RubyOnVibes.agent_tasks?
  rescue
    false
  end

  def referrals_enabled?
    defined?(Refer) && RubyOnVibes.config.referrals?
  rescue
    false
  end

  def profile_path_safe
    edit_profile_registration_path
  rescue
    "/profile/registration/edit"
  end

  def password_path_safe
    edit_profile_password_path
  rescue
    "/profile/password/edit"
  end
  
  # Safe wrapper for hotwire_native_app? helper (may not exist in all contexts)
  def hotwire_native_app_safe?
    return false unless respond_to?(:hotwire_native_app?)
    hotwire_native_app?
  rescue
    false
  end

  private

  def current_workspace_attrs
    return nil unless current_workspace
    {
      id: current_workspace.to_param,
      name: current_workspace.name,
      personal: current_workspace.personal?,
      membersCount: current_workspace.members_count
    }
  end
  
  def current_member_attrs
    return nil unless current_member
    {
      id: current_member.to_param,
      username: current_member.user.username,
      roles: current_member.active_roles,
      isOwner: current_member.workspace_owner?
    }
  end

  def devise_canvas?
    defined?(controller_path) &&
      controller_path&.start_with?("authentication/")
  end
  
  # Email-safe inline button styles
  # Use this for links in email templates to ensure consistent, reliable button styling
  # Example: <%= link_to "Click Me", url, style: email_button_style(:primary) %>
  def email_button_style(variant = :primary)
    tokens = vibes_tokens
    base = "display:inline-block;padding:12px 32px;font-size:15px;font-weight:600;text-decoration:none;border-radius:6px;text-align:center;"
    
    case variant
    when :primary
      "#{base}background-color:rgb(#{tokens[:brand]});color:rgb(#{tokens[:brand_contrast]});"
    when :secondary
      "#{base}background-color:rgb(#{tokens[:surface_2]});color:rgb(#{tokens[:text_1]});border:1px solid rgb(#{tokens[:surface_3]});"
    else
      base
    end
  end

end
