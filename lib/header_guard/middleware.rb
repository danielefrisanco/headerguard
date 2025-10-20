# frozen_string_literal: true

module HeaderGuard
  # The Rack middleware class responsible for injecting security headers.
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
      # 2. Merge remaining options (which are custom headers) over the defaults.
      # THIS IS THE FIX: By merging 'config' (which now only contains headers)
      # over the defaults, the user's header values take precedence.
      @headers = DEFAULT_HEADERS.merge(config).freeze

      # Set the final CSP value and the header key based on report_only setting
      @csp_value = custom_csp || DEFAULT_CSP
      @csp_header_key = @report_only ? "Content-Security-Policy-Report-Only" : "Content-Security-Policy"
    end

    # The Rack application call method.
    def call(env)
      status, headers, body = @app.call(env)

      # Only inject headers on successful (2xx) responses with HTML content.
      # Exclude redirects, errors, and non-HTML assets (like JSON or images).
      if (200..299).include?(status) && headers["Content-Type"]&.include?("text/html")
        
        # Inject the standard headers
        @headers.each do |key, value|
          # We use assignment (=) here, not `||=`, to ensure the middleware
          # overwrites any headers set by the application before it,
          # adhering to the strong security posture.
          headers[key] = value 
        end
        
        # Inject the configured CSP header
        headers[@csp_header_key] = @csp_value
      end

      [status, headers, body]
    end
  end
end
