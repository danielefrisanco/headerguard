# frozen_string_literal: true

module HeaderGuard
  # The Rack middleware class responsible for injecting security headers.
  #
  # Header names are treated case-insensitively throughout. The Rack 3 SPEC
  # requires response header keys to be lowercase, while Rack 2 applications
  # conventionally use capitalized keys, so this middleware reads incoming
  # headers case-insensitively and always writes lowercase keys.
  class Middleware
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

      # Only inject headers on successful (2xx) responses with HTML content.
      # Exclude redirects, errors, and non-HTML assets (like JSON or images).
      if (200..299).include?(status) && html?(headers)
        # Inject the standard headers
        @headers.each do |key, value|
          # We use assignment here, not `||=`, to ensure the middleware
          # overwrites any headers set by the application before it,
          # adhering to the strong security posture.
          assign(headers, key, value)
        end

        # Inject the configured CSP header
        assign(headers, @csp_header_key, @csp_value)
      end

      [status, headers, body]
    end

    private

    def normalize_key(key)
      key.to_s.downcase
    end

    def html?(headers)
      fetch_header(headers, "content-type")&.include?("text/html")
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
