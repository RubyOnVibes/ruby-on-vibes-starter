module AvatarsHelper
  # Avatar Resolution for Users, Workspaces, and other records
  #
  # Vibes uses a cascading fallback strategy for avatars:
  #   1. Uploaded avatar (ActiveStorage)
  #   2. Gravatar (if email available)
  #   3. Initials-based avatar (UI Avatars)
  #
  # This differs from simple gravatar-only fallbacks by providing
  # a richer visual experience with letter-based defaults.

  # Resolves the best available avatar for any record
  #
  # @param record [User, Workspace, Invitation, #email] Any record with optional avatar/email
  # @param opts [Hash] Options for avatar generation
  # @option opts [Integer] :size (48) Pixel dimensions for the avatar
  # @option opts [String] :fallback (:initials) Fallback strategy - :initials, :gravatar, or :mystery
  # @return [String, ActiveStorage::Variant] URL or variant for the avatar
  #
  # @example Basic usage
  #   <%= image_tag avatar_url(current_user) %>
  #
  # @example With size
  #   <%= image_tag avatar_url(@member.user, size: 128) %>
  #
  # @example Force gravatar fallback
  #   <%= image_tag avatar_url(record, fallback: :gravatar) %>
  #
  def avatar_url(record, opts = {})
    size = opts.fetch(:size, 48)
    fallback = opts.fetch(:fallback, :initials)

    # Priority 1: Uploaded avatar via ActiveStorage
    if has_uploaded_avatar?(record)
      return record.avatar.variant(resize_to_fit: [size, size])
    end

    # Priority 2+: Fallback based on strategy
    email = extract_email(record)
    name = extract_display_name(record)

    case fallback
    when :gravatar, :mystery
      gravatar_url_for(email, size: size)
    when :initials
      # Prefer initials for a more personalized look, gravatar as last resort
      if name.present?
        ui_avatar_url(name: name, size: size, background: "random")
      else
        gravatar_url_for(email, size: size)
      end
    else
      gravatar_url_for(email, size: size)
    end
  end

  # Generates a Gravatar URL from an email address
  #
  # Gravatar uses MD5 hashing of lowercase email addresses.
  # See: https://docs.gravatar.com/general/images/
  #
  # @param email [String, nil] Email address to hash
  # @param size [Integer] Image size in pixels (1-2048)
  # @param default [Symbol] Default image style (:mp, :identicon, :monsterid, :wavatar, :retro, :robohash)
  # @param rating [Symbol] Content rating (:g, :pg, :r, :x)
  # @return [String] Gravatar image URL
  #
  def gravatar_url_for(email, size: 64, default: :mp, rating: :pg)
    normalized_email = email.to_s.strip.downcase
    hash = Digest::MD5.hexdigest(normalized_email)

    query = { d: default, r: rating, s: size }.to_query
    "https://www.gravatar.com/avatar/#{hash}?#{query}"
  end

  # Generates a UI Avatars URL for initials-based avatars
  #
  # Creates colorful letter-based avatars from names.
  # See: https://ui-avatars.com/
  #
  # @param name [String] Name to extract initials from
  # @param size [Integer] Image size in pixels
  # @param background [String] Background color (hex without #) or "random"
  # @param color [String] Text color (hex without #)
  # @param bold [Boolean] Use bold font weight
  # @param rounded [Boolean] Make avatar circular
  # @return [String] UI Avatars image URL
  #
  def ui_avatar_url(name:, size: 64, background: "random", color: "fff", bold: true, rounded: true, **extra)
    params = {
      name: name,
      size: size,
      background: background,
      color: color,
      bold: bold,
      rounded: rounded
    }.merge(extra)

    "https://ui-avatars.com/api/?#{params.to_query}"
  end


  # ============================================================================
  # Workspace Display
  # ============================================================================

  ##
  # Renders an avatar image for a workspace.
  #
  # Avatar resolution strategy:
  #   1. Personal workspace owned by current user → user's avatar
  #   2. Workspace has uploaded avatar → resized variant
  #   3. Fallback → initials-based avatar from workspace name
  #
  # @param workspace [Workspace] the workspace to render avatar for
  # @param css_class [String] Tailwind size class (e.g., "size-8", "size-12")
  # @param pixel_size [Integer] pixel dimensions for image resizing
  # @return [String] HTML img tag
  #
  # @example Basic usage
  #   <%= workspace_avatar(@workspace) %>
  #
  # @example Custom size
  #   <%= workspace_avatar(@workspace, css_class: "size-16", pixel_size: 128) %>
  #
  def workspace_avatar(workspace, css_class: "size-8", pixel_size: 48)
    base_classes = "rounded-full shrink-0 object-cover"
    combined_classes = [base_classes, css_class].join(" ")

    image_src = resolve_workspace_avatar_src(workspace, pixel_size)
    image_tag(image_src, class: combined_classes, alt: workspace.name)
  end

  private

  def has_uploaded_avatar?(record)
    record.respond_to?(:avatar) &&
      record.avatar.attached? &&
      record.avatar.variable?
  end

  def extract_email(record)
    return record.email if record.respond_to?(:email)
    return record.user&.email if record.respond_to?(:user)
    nil
  end

  def extract_display_name(record)
    # Try common name methods
    return record.name if record.respond_to?(:name) && record.name.present?
    return record.full_name if record.respond_to?(:full_name) && record.full_name.present?
    return "#{record.first_name} #{record.last_name}".strip if record.respond_to?(:first_name)

    # For join models, try the user
    if record.respond_to?(:user)
      user = record.user
      return user.name if user&.name.present?
    end

    nil
  end
end

