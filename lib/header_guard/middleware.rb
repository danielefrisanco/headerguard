# frozen_string_literal: true

module HeaderGuard
  # The Rack middleware class responsible for injecting security headers.
  #
  # Header names are treated case-insensitively throughout. The Rack 3 SPEC
  # requires response header keys to be lowercase, while Rack 2 applications
  # conventionally use capitalized keys, so this middleware reads incoming
  # headers case-insensitively and always writes lowercase keys.
  #
  # Which responses receive which headers:
  #
  # * The standard headers (HSTS, X-Content-Type-Options, X-Frame-Options,
  #   Referrer-Policy) are applied to every response, regardless of status or
  #   content type. HSTS matters most on the HTTP->HTTPS redirect, and nosniff
  #   exists precisely to protect non-HTML bodies such as JSON.
  # * The Content Security Policy governs a document, so it is applied only to
  #   HTML responses -- but on every status. Error pages reflect user input and
  #   are a classic XSS surface, so they need a policy at least as much as a
  #   200 does.
  #
  # Passing `html_only: true` restores the 0.1.x behaviour, where nothing was
  # injected unless the response was a 2xx with an HTML content type.
  class Middleware
    # Content types treated as HTML documents for the purpose of applying CSP.
    HTML_CONTENT_TYPES = ["text/html", "application/xhtml+xml"].freeze

    # Initializes the middleware. It merges user-defined options over defaults.
    #
    # @param app [Object] The next application in the Rack stack.
    # @param options [Hash] Configuration options for headers and CSP.
    def initialize(app, options = {})
      @app = app

      # Use a copy of options for configuration extraction
      config = options.dup

      # Extract special configuration settings
      custom_csp = config.delete(:content_security_policy)
      @report_only = config.delete(:report_only) || false
      @html_only = config.delete(:html_only) || false

      # 1. Start with DEFAULT_HEADERS (from header_guard.rb)
      # 2. Merge remaining options (which are custom headers) over the defaults,
      #    so the user's header values take precedence.
      # 3. Normalize every key to lowercase, so a custom "X-Frame-Options"
      #    overrides the default rather than being emitted alongside it.
      @headers = DEFAULT_HEADERS.merge(config).each_with_object({}) do |(key, value), normalized|
        normalized[normalize_key(key)] = value
      end.freeze

      # Set the final CSP value and the header key based on report_only setting
      @csp_value = custom_csp || DEFAULT_CSP
      @csp_header_key = @report_only ? "content-security-policy-report-only" : "content-security-policy"
    end

    # The Rack application call method.
    def call(env)
      status, headers, body = @app.call(env)

      html = html?(headers)

      if apply_standard_headers?(status, html)
        @headers.each do |key, value|
          # We use assignment here, not `||=`, to ensure the middleware
          # overwrites any headers set by the application before it,
          # adhering to the strong security posture.
          assign(headers, key, value)
        end
      end

      assign(headers, @csp_header_key, @csp_value) if apply_csp?(status, html)

      [status, headers, body]
    end

    private

    # Standard headers go on every response. In html_only mode they are
    # restricted to 2xx HTML, as in 0.1.x.
    def apply_standard_headers?(status, html)
      return true unless @html_only

      success?(status) && html
    end

    # CSP goes on every HTML response regardless of status. In html_only mode
    # it is restricted to 2xx HTML, as in 0.1.x.
    def apply_csp?(status, html)
      return false unless html
      return true unless @html_only

      success?(status)
    end

    def success?(status)
      (200..299).cover?(status)
    end

    def normalize_key(key)
      key.to_s.downcase
    end

    def html?(headers)
      content_type = fetch_header(headers, "content-type")
      return false unless content_type

      HTML_CONTENT_TYPES.any? { |type| content_type.include?(type) }
    end

    # Rack 3 responses key headers in lowercase; Rack 2 applications typically
    # send "Content-Type". A Rack::Headers hash resolves either directly, but a
    # plain Hash does not, so fall back to scanning for a case-insensitive match.
    def fetch_header(headers, key)
      return headers[key] if headers.key?(key)

      match = headers.keys.find { |candidate| normalize_key(candidate) == key }
      match && headers[match]
    end

    # Writes the lowercase key, first removing any differently-cased duplicate
    # the application may have set, so the response never carries the same
    # header twice under two spellings.
    def assign(headers, key, value)
      headers.keys.each do |existing|
        next if existing == key

        headers.delete(existing) if normalize_key(existing) == key
      end

      headers[key] = value
    end
  end
end
