# frozen_string_literal: true

require_relative "header_guard/version"
require_relative "header_guard/middleware"

module HeaderGuard
  # Standard security headers applied by default.
  DEFAULT_HEADERS = {
    # Strictly enforce HTTPS, preventing protocol downgrade attacks.
    # 1 year (31536000 seconds) max-age is standard best practice.
    "Strict-Transport-Security"   => "max-age=31536000; includeSubDomains; preload",
    # Prevent the browser from trying to guess the content type,
    # which can lead to XSS attacks if it misinterprets a file as a script.
    "X-Content-Type-Options"      => "nosniff",
    # Tells the browser which referrer information to include with requests.
    # origin-when-cross-origin is a good balance of security and functionality.
    "X-Frame-Options"             => "DENY",
    # Tells the browser which referrer information to include with requests.
    # origin-when-cross-origin is a good balance of security and functionality.
    "Referrer-Policy"             => "strict-origin-when-cross-origin"
  }.freeze

  # Default Content Security Policy. This is a secure baseline.
  # This serves as a strong baseline, allowing resources only from the same origin ('self'),
  # and explicitly blocking all plugins, base tags, and object embeds.
  #
  # Note: A real application will likely need to customize this heavily
  # to allow CDNs, analytics scripts, etc.
  DEFAULT_CSP = (
    "default-src 'self';" \
    "base-uri 'self';" \
    "font-src 'self' https: data:;" \
    "form-action 'self';" \
    "frame-ancestors 'none';" \
    "object-src 'none';" \
    "script-src 'self';" \
    "style-src 'self' 'unsafe-inline' https:;" \
    "upgrade-insecure-requests;" \
    "block-all-mixed-content"
  ).freeze
end
