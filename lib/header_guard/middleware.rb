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
  #   Referrer-Policy, ...) are applied to every response, regardless of status
  #   or content type. HSTS matters most on the HTTP->HTTPS redirect, and
  #   nosniff exists precisely to protect non-HTML bodies such as JSON.
  # * The Content Security Policy governs a document, so it is applied only to
  #   HTML responses -- but on every status. Error pages reflect user input and
  #   are a classic XSS surface, so they need a policy at least as much as a
  #   200 does.
  #
  # Options are validated at construction and raise ArgumentError on anything
  # unrecognised or malformed, so a typo cannot silently weaken the policy.
  class Middleware
    # Content types treated as HTML documents for the purpose of applying CSP.
    HTML_CONTENT_TYPES = ["text/html", "application/xhtml+xml"].freeze

    # Symbol keys with special meaning. Every other key must be a String naming
    # a header; any other Symbol is a typo and is rejected.
    OPTION_KEYS = %i[content_security_policy report_only html_only path_overrides].freeze

    # Headers set through their own option rather than as a raw header, so the
    # two mechanisms cannot silently fight over the same response header.
    RESERVED_HEADERS = ["content-security-policy", "content-security-policy-report-only"].freeze

    # Headers whose effect is host-wide rather than per-document. Sending a
    # weaker value on one path would weaken it for the whole site, so they may
    # not appear in path_overrides.
    HOST_SCOPED_HEADERS = ["strict-transport-security"].freeze

    # The RFC 7230 token alphabet: the only characters legal in a header name.
    HEADER_NAME = /\A[!#$%&'*+\-.^_`|~0-9A-Za-z]+\z/.freeze

    # Any control character in a header value is rejected. CR and LF in
    # particular would let a value inject further headers or a whole second
    # response (response splitting).
    CONTROL_CHARS = /[\x00-\x1F\x7F]/.freeze

    CSP_HEADER = "content-security-policy"
    CSP_REPORT_ONLY_HEADER = "content-security-policy-report-only"

    # Fully resolved configuration for one scope: the whole site, or one path.
    # `csp_value` is nil when CSP is disabled for the scope.
    Policy = Struct.new(:headers, :csp_key, :csp_value, :html_only, keyword_init: true)

    # Initializes the middleware. It merges user-defined options over defaults.
    #
    # @param app [Object] The next application in the Rack stack.
    # @param options [Hash] Configuration options for headers and CSP.
    # @raise [ArgumentError] on any unknown option, malformed header name or
    #   value, or a path override that would weaken a host-scoped header.
    def initialize(app, options = {})
      @app = app

      raise ArgumentError, "HeaderGuard options must be a Hash, got #{options.class}" unless options.is_a?(Hash)

      defaults = Policy.new(
        headers: normalize_keys(DEFAULT_HEADERS),
        csp_key: CSP_HEADER,
        csp_value: DEFAULT_CSP,
        html_only: false
      )

      @policy = build_policy(options, defaults, path: nil)
      @path_policies = build_path_policies(options[:path_overrides])
    end

    # The Rack application call method.
    def call(env)
      status, headers, body = @app.call(env)

      policy = policy_for(env["PATH_INFO"])
      html = html?(headers)

      if apply_standard_headers?(policy, status, html)
        policy.headers.each do |key, value|
          # We use assignment here, not `||=`, to ensure the middleware
          # overwrites any headers set by the application before it,
          # adhering to the strong security posture.
          assign(headers, key, value)
        end
      end

      assign(headers, policy.csp_key, policy.csp_value) if policy.csp_value && apply_csp?(policy, status, html)

      [status, headers, body]
    end

    private

    # ------------------------------------------------------------------
    # Configuration
    # ------------------------------------------------------------------

    # Layers one options Hash over a base Policy. Used once for the global
    # options over the defaults, and once per path override over the global
    # policy, so an override inherits everything it does not mention.
    def build_policy(options, base, path:)
      headers = base.headers.dup
      csp_value = base.csp_value
      report_only = base.csp_key == CSP_REPORT_ONLY_HEADER
      html_only = base.html_only

      options.each do |key, value|
        case key
        when :content_security_policy
          csp_value = resolve_csp(value, csp_value)
        when :report_only
          report_only = resolve_flag(key, value, report_only)
        when :html_only
          html_only = resolve_flag(key, value, html_only)
        when :path_overrides
          raise ArgumentError, "path_overrides cannot be nested inside the override for #{path.inspect}" if path
        when String
          name = validate_header_name(key, path)
          if value.nil? || value == false
            headers.delete(name)
          else
            headers[name] = validate_header_value(key, value)
          end
        else
          raise ArgumentError,
                "unknown HeaderGuard option #{key.inspect}. Recognised options are " \
                "#{OPTION_KEYS.map(&:inspect).join(', ')}; custom headers must be given as String keys."
        end
      end

      Policy.new(
        headers: headers.freeze,
        csp_key: report_only ? CSP_REPORT_ONLY_HEADER : CSP_HEADER,
        csp_value: csp_value,
        html_only: html_only
      )
    end

    def build_path_policies(overrides)
      return [].freeze if overrides.nil?

      unless overrides.is_a?(Hash)
        raise ArgumentError, "path_overrides must be a Hash of path matcher => options, got #{overrides.class}"
      end

      overrides.map do |matcher, options|
        unless matcher.is_a?(String) || matcher.is_a?(Regexp)
          raise ArgumentError, "path_overrides keys must be a String (exact path) or a Regexp, got #{matcher.inspect}"
        end
        unless options.is_a?(Hash)
          raise ArgumentError, "path_overrides[#{matcher.inspect}] must be an options Hash, got #{options.class}"
        end

        [matcher, build_policy(options, @policy, path: matcher)]
      end.freeze
    end

    # nil keeps the inherited value (so an unset ENV var cannot silently
    # disable CSP); false disables CSP for the scope; a String replaces it.
    def resolve_csp(value, current)
      case value
      when nil then current
      when false then nil
      when String then validate_header_value(:content_security_policy, value)
      else
        raise ArgumentError, "content_security_policy must be a String, false, or nil, got #{value.inspect}"
      end
    end

    def resolve_flag(key, value, current)
      return current if value.nil?
      return value if value == true || value == false

      raise ArgumentError, "#{key} must be true or false, got #{value.inspect}"
    end

    def validate_header_name(key, path)
      raise ArgumentError, "#{key.inspect} is not a valid HTTP header name" unless key.match?(HEADER_NAME)

      name = key.downcase

      if RESERVED_HEADERS.include?(name)
        raise ArgumentError,
              "#{key} cannot be set as a raw header; use the content_security_policy: and report_only: options"
      end

      if path && HOST_SCOPED_HEADERS.include?(name)
        raise ArgumentError,
              "#{key} cannot be overridden for #{path.inspect}: it is host-scoped, not per-document, " \
              "so a value sent on one path would apply to the whole site"
      end

      name
    end

    def validate_header_value(key, value)
      unless value.is_a?(String)
        raise ArgumentError, "value for #{key.inspect} must be a String, got #{value.inspect}"
      end
      if value.empty?
        raise ArgumentError, "value for #{key.inspect} is empty; pass nil to remove the header instead"
      end
      if value.match?(CONTROL_CHARS)
        raise ArgumentError,
              "value for #{key.inspect} contains a control character (CR, LF, ...), which would allow " \
              "header injection or response splitting"
      end

      value
    end

    def normalize_keys(headers)
      headers.each_with_object({}) do |(key, value), normalized|
        normalized[normalize_key(key)] = value
      end
    end

    def normalize_key(key)
      key.to_s.downcase
    end

    # ------------------------------------------------------------------
    # Per-request
    # ------------------------------------------------------------------

    # First matching override wins; none matching means the global policy.
    def policy_for(path)
      path = path.to_s

      @path_policies.each do |matcher, policy|
        matched = matcher.is_a?(Regexp) ? matcher.match?(path) : matcher == path
        return policy if matched
      end

      @policy
    end

    # Standard headers go on every response. In html_only mode they are
    # restricted to 2xx HTML, as in 0.1.x.
    def apply_standard_headers?(policy, status, html)
      return true unless policy.html_only

      success?(status) && html
    end

    # CSP goes on every HTML response regardless of status. In html_only mode
    # it is restricted to 2xx HTML, as in 0.1.x.
    def apply_csp?(policy, status, html)
      return false unless html
      return true unless policy.html_only

      success?(status)
    end

    def success?(status)
      (200..299).cover?(status)
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
