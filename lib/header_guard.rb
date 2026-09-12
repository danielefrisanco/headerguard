# frozen_string_literal: true

require_relative "header_guard/version"
require_relative "header_guard/middleware"

module HeaderGuard
  # Standard security headers applied to every response by default.
  DEFAULT_HEADERS = {
    # Strictly enforce HTTPS for one year, including subdomains, preventing
    # protocol downgrade attacks.
    #
    # `preload` is deliberately omitted. It is the opt-in signal for the browser
    # HSTS preload list, which hard-codes the apex domain and every subdomain as
    # HTTPS-only inside the browser itself, and removal from the list takes
    # months. That is a commitment to make explicitly, not one to acquire by
    # adding a middleware. Opt in with:
    #   "Strict-Transport-Security" => "max-age=31536000; includeSubDomains; preload"
    "Strict-Transport-Security"          => "max-age=31536000; includeSubDomains",
    # Prevent the browser from guessing the content type, which can lead to XSS
    # if it misinterprets a file as a script.
    "X-Content-Type-Options"             => "nosniff",
    # Forbid rendering this site inside a frame, preventing clickjacking. The
    # legacy counterpart of the CSP `frame-ancestors` directive below.
    "X-Frame-Options"                    => "DENY",
    # Send the full referrer only on same-origin requests, and just the origin
    # cross-origin; a good balance of security and functionality.
    "Referrer-Policy"                    => "strict-origin-when-cross-origin",
    # Put this site in its own browsing context group, so a cross-origin window
    # that opens it (or that it opens) cannot hold a reference to it. Mitigates
    # XS-Leaks and Spectre-class attacks.
    #
    # Popup-based auth flows that rely on `window.opener` need
    # "same-origin-allow-popups" (this site opens the popup) or "unsafe-none"
    # (this site *is* the popup). Redirect-based flows are unaffected.
    "Cross-Origin-Opener-Policy"         => "same-origin",
    # Prevent other origins from embedding this site's resources (images,
    # scripts, fonts) via no-cors requests. Override with "cross-origin" on
    # assets that are meant to be embedded elsewhere.
    "Cross-Origin-Resource-Policy"       => "same-origin",
    # Forbid Adobe Flash / Acrobat cross-domain policy files.
    "X-Permitted-Cross-Domain-Policies"  => "none",
    # Deny access to sensitive device features unless explicitly enabled.
    "Permissions-Policy"                 => "accelerometer=(), camera=(), geolocation=(), gyroscope=(), " \
                                            "magnetometer=(), microphone=(), payment=(), usb=()"
  }.freeze

  # Default Content Security Policy: a strict same-origin baseline.
  #
  # Resources may load only from this origin; plugins, <base> tags and object
  # embeds are blocked outright; inline scripts and styles are not permitted.
  #
  # A real application will need to extend this -- to allow a CDN, an analytics
  # script, inline styles -- but should do so by adding the specific origins or
  # nonces it needs, not by reintroducing broad sources such as `https:` or
  # `'unsafe-inline'`. Both let an attacker who can inject markup load or run
  # content from an origin of their choosing.
  DEFAULT_CSP = [
    "default-src 'self'",
    "base-uri 'self'",
    "font-src 'self'",
    "form-action 'self'",
    "frame-ancestors 'none'",
    "object-src 'none'",
    "script-src 'self'",
    "style-src 'self'",
    "upgrade-insecure-requests"
  ].join("; ").freeze
end
