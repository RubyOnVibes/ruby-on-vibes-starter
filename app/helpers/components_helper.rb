module ComponentsHelper
  # UI Components - Generic reusable view components
  # Consolidates: BadgesHelper, ButtonsHelper, NavHelper

  # ==================== BADGES ====================
  
  # Renders a badge component
  # @example
  #   <%= badge "Active", color: "bg-success/10 text-success" %>
  #   <%= badge color: "bg-success/10 text-success" do %>
  #     <svg>...</svg> Active
  #   <% end %>
  def badge(text = nil, options = {}, &block)
    text, options = nil, text || {} if block
    base = options.delete(:base) || "rounded-sm py-0.5 px-2 text-xs inline-block font-semibold leading-normal mr-2"
    color = options.delete(:color) || "bg-muted text-muted-foreground"
    options[:class] = Array.wrap(options[:class]) + [base, color]
    tag.div(text, **options, &block)
  end

  # ==================== BUTTONS ====================
  
  # Generates button text with loading state for Turbo
  # Preserves opacity-25 opacity-75 during purge
  # @example
  #   <%= button_to "Save", path, class: "btn" do %>
  #     <%= button_text "Save", disable_with: "Saving..." %>
  #   <% end %>
  def button_text(text = nil, disable_with: t("processing"), &block)
    text = capture(&block) if block

    tag.span(text, class: "when-enabled") +
      tag.span(class: "when-disabled") do
        <<~ICON.html_safe + disable_with
          <svg class="animate-spin inline-block mr-2 h-4 w-4" xmlns="http://www.w3.org/2000/svg" fill="none" viewBox="0 0 24 24">
            <circle class="opacity-25" cx="12" cy="12" r="10" stroke="currentColor" stroke-width="4"></circle>
            <path class="opacity-75" fill="currentColor" d="M4 12a8 8 0 018-8V0C5.373 0 0 5.373 0 12h4zm2 5.291A7.962 7.962 0 014 12H0c0 3.042 1.135 5.824 3 7.938l3-2.647z"></path>
          </svg>
        ICON
      end
  end

  # ==================== NAVIGATION ====================
  
  # Renders a link with active state highlighting
  # @example
  #   <%= active_link_to "Dashboard", dashboard_path, active_class: "font-bold" %>
  #   <%= active_link_to dashboard_path, starts_with: "/dashboard" do %>
  #     Dashboard
  #   <% end %>
  def active_link_to(name = nil, options = {}, html_options = {}, &block)
    if block
      html_options = options
      options = name
      name = block
    end

    url = url_for(options)
    starts_with = html_options.delete(:starts_with)
    html_options[:class] = Array.wrap(html_options[:class])
    active_class = html_options.delete(:active_class) || "active"
    inactive_class = html_options.delete(:inactive_class) || ""

    paths = Array.wrap(starts_with)
    active = if paths.present?
      paths.any? { |path| request.path.start_with?(path) }
    else
      request.path == url
    end

    classes = active ? active_class : inactive_class
    html_options[:class] << classes unless classes.empty?

    html_options.except!(:class) if html_options[:class].empty?

    return link_to url, html_options, &block if block

    link_to name, url, html_options
  end

  # Generates a header with an anchor link for sharing
  # @example
  #   <%= anchor_header "Section Title", header_tag: :h2 %>
  def anchor_header(title, header_tag: :h2, id: nil, icon: nil, header_class: "group", link_class: "hidden align-middle group-hover:inline-block p-1", icon_class: "text-muted-foreground h-4 w-4")
    id ||= title.parameterize
    icon ||= <<~LINK.html_safe
      <svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 24 24" fill="currentColor" class="#{icon_class}">
        <path fill-rule="evenodd" d="M19.902 4.098a3.75 3.75 0 0 0-5.304 0l-4.5 4.5a3.75 3.75 0 0 0 1.035 6.037.75.75 0 0 1-.646 1.353 5.25 5.25 0 0 1-1.449-8.45l4.5-4.5a5.25 5.25 0 1 1 7.424 7.424l-1.757 1.757a.75.75 0 1 1-1.06-1.06l1.757-1.757a3.75 3.75 0 0 0 0-5.304Zm-7.389 4.267a.75.75 0 0 1 1-.353 5.25 5.25 0 0 1 1.449 8.45l-4.5 4.5a5.25 5.25 0 1 1-7.424-7.424l1.757-1.757a.75.75 0 1 1 1.06 1.06l-1.757 1.757a3.75 3.75 0 1 0 5.304 5.304l4.5-4.5a3.75 3.75 0 0 0-1.035-6.037.75.75 0 0 1-.354-1Z" clip-rule="evenodd" />
      </svg>
    LINK
    tag.send(header_tag, id: id, class: header_class) do
      tag.span(title) + link_to(icon, "##{id}", class: link_class)
    end
  end

  # Convenience methods for h1-h6 with anchors
  (1..6).each do |i|
    define_method :"h#{i}_with_anchor" do |*args, **kwargs|
      anchor_header(*args, **kwargs.merge(header_tag: :"h#{i}"))
    end
  end
end

