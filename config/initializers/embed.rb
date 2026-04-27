# Allow embedding when app is used inside an iframe on the platform

Rails.application.configure do
  allow_iframe = (ENV['EMBED_ALLOW_IFRAME'] == 'true') || Rails.env.development? || Rails.env.test?

  # Default localhost ports for dev/test only
  default_allowlist = if Rails.env.development? || Rails.env.test?
    [
      'http://localhost:3000',
      'http://localhost:3001',
      'http://localhost:3002',
      'http://localhost:3003',
      'http://localhost:3004',
      'http://localhost:3005'
    ]
  else
    []
  end

  env_allowlist = (ENV['EMBED_ALLOWLIST'] || '').split(',').map(&:strip).reject(&:blank?)
  allowlist = (env_allowlist + default_allowlist).uniq

  # In production, if embedding is enabled, require an explicit allowlist
  if Rails.env.production? && allow_iframe && allowlist.blank?
    raise 'EMBED_ALLOWLIST is not set'
  end

  if allow_iframe
    # Per-app session cookie key prevents cross-app cookie collisions when
    # multiple apps share an eTLD+1 domain
    cookie_key = (ENV['SESSION_COOKIE_KEY'].presence || '_rov_session')
    config.session_store :cookie_store, key: cookie_key

    # Allow embedding via CSP frame-ancestors and X-Frame-Options
    begin
      # Prefer CSP over X-Frame-Options; remove header so CSP governs embedding
      config.action_dispatch.default_headers.delete('X-Frame-Options')
      config.content_security_policy do |p|
        # Default to self; extend with allowlist if provided
        if allowlist.any?
          p.frame_ancestors :self, *allowlist
        else
          p.frame_ancestors :self
        end

        # CRITICAL: Allow inline PDF viewing (for receipts/invoices via Pay gem)
        # Without this, Chrome blocks PDFs with ERR_BLOCKED_BY_CLIENT
        p.object_src :self, :blob

        # Allow Stripe embedded checkout iframes
        p.frame_src :self, :blob, 'https://js.stripe.com', 'https://*.stripe.com'

        # Allow Stripe API connections
        p.connect_src :self, 'https://api.stripe.com', 'wss://*.stripe.com'
      end
    rescue => e
      Rails.logger.warn "[Vibes embed] CSP/XFO config failed: #{e.message}"
    end
  end
end
