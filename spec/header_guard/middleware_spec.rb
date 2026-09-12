# frozen_string_literal: true

# Require the necessary components for testing
require "rack/test"
require "rack"
require "header_guard"
require "header_guard/middleware"

# Mock Rack application to test the middleware against.
# Returns a standard 2xx HTML response; other statuses and content types are
# exercised with inline lambdas in the "Response Scope" tests below.
class MockApp
  def call(_env)
    [200, { "Content-Type" => "text/html" }, ["<h1>Hello!</h1>"]]
  end
end

RSpec.describe HeaderGuard::Middleware do
  include Rack::Test::Methods

  # Setup method to inject our middleware into the Rack app chain
  def app(options = {})
    # Use the Middleware with the MockApp
    Rack::Builder.new do
      use HeaderGuard::Middleware, options
      run MockApp.new
    end
  end

  let(:default_headers) { HeaderGuard::DEFAULT_HEADERS }
  let(:default_csp) { HeaderGuard::DEFAULT_CSP }

  # ====================================================================
  # CORE FUNCTIONALITY TESTS
  # ====================================================================

  describe "Header Injection on HTML Responses" do
    before { get "/" }

    it "returns a successful status code" do
      expect(last_response.status).to eq(200)
    end

    it "injects all default security headers" do
      default_headers.each do |header, value|
        expect(last_response.headers[header]).to eq(value), "Expected header '#{header}' to be present with value '#{value}'"
      end
    end

    it "injects the default Content-Security-Policy header" do
      expect(last_response.headers["Content-Security-Policy"]).to eq(default_csp)
    end

    it "does not inject the Report-Only CSP header by default" do
      expect(last_response.headers["Content-Security-Policy-Report-Only"]).to be_nil
    end
  end

  # ====================================================================
  # RESPONSE SCOPE TESTS
  #
  # Standard headers (HSTS, nosniff, X-Frame-Options, Referrer-Policy) apply
  # to every response. CSP applies to every HTML response regardless of
  # status. These are the responses that most need protection: the
  # HTTP->HTTPS redirect for HSTS, JSON bodies for nosniff, and error pages
  # -- which reflect user input -- for CSP.
  # ====================================================================

  describe "Response Scope" do
    let(:env) { Rack::MockRequest.env_for("http://example.com/") }

    def headers_for(status, response_headers, options = {})
      inner = ->(_env) { [status, response_headers, ["body"]] }
      described_class.new(inner, options).call(env)[1]
    end

    def expect_standard_headers(headers)
      default_headers.each do |header, value|
        expect(headers[header.downcase]).to eq(value), "Expected '#{header.downcase}' to be present"
      end
    end

    def expect_no_standard_headers(headers)
      default_headers.each_key do |header|
        expect(headers[header.downcase]).to be_nil, "Expected '#{header.downcase}' to be absent"
      end
    end

    it "applies standard headers but not CSP to a JSON response" do
      headers = headers_for(200, { "content-type" => "application/json" })

      expect_standard_headers(headers)
      expect(headers["content-security-policy"]).to be_nil
    end

    it "applies standard headers (including HSTS) to a redirect" do
      headers = headers_for(302, { "location" => "/new" })

      expect_standard_headers(headers)
      expect(headers["content-security-policy"]).to be_nil
    end

    it "applies standard headers to a response with no content-type at all" do
      headers = headers_for(204, {})

      expect_standard_headers(headers)
      expect(headers["content-security-policy"]).to be_nil
    end

    it "applies CSP and standard headers to an HTML 500 error page" do
      headers = headers_for(500, { "content-type" => "text/html" })

      expect_standard_headers(headers)
      expect(headers["content-security-policy"]).to eq(default_csp)
    end

    it "applies CSP and standard headers to an HTML 404 page" do
      headers = headers_for(404, { "content-type" => "text/html; charset=utf-8" })

      expect_standard_headers(headers)
      expect(headers["content-security-policy"]).to eq(default_csp)
    end

    it "applies standard headers but not CSP to a JSON 404" do
      headers = headers_for(404, { "content-type" => "application/json" })

      expect_standard_headers(headers)
      expect(headers["content-security-policy"]).to be_nil
    end

    it "treats application/xhtml+xml as HTML for CSP" do
      headers = headers_for(200, { "content-type" => "application/xhtml+xml" })

      expect(headers["content-security-policy"]).to eq(default_csp)
    end

    it "uses the report-only CSP header on error pages when configured" do
      headers = headers_for(500, { "content-type" => "text/html" }, report_only: true)

      expect(headers["content-security-policy-report-only"]).to eq(default_csp)
      expect(headers["content-security-policy"]).to be_nil
    end

    describe "html_only: true (0.1.x behaviour)" do
      let(:legacy) { { html_only: true } }

      it "still injects everything on a 2xx HTML response" do
        headers = headers_for(200, { "content-type" => "text/html" }, legacy)

        expect_standard_headers(headers)
        expect(headers["content-security-policy"]).to eq(default_csp)
      end

      it "injects nothing on a JSON response" do
        headers = headers_for(200, { "content-type" => "application/json" }, legacy)

        expect_no_standard_headers(headers)
        expect(headers["content-security-policy"]).to be_nil
      end

      it "injects nothing on a redirect" do
        headers = headers_for(302, { "location" => "/new" }, legacy)

        expect_no_standard_headers(headers)
        expect(headers["content-security-policy"]).to be_nil
      end

      it "injects nothing on an HTML 500 error page" do
        headers = headers_for(500, { "content-type" => "text/html" }, legacy)

        expect_no_standard_headers(headers)
        expect(headers["content-security-policy"]).to be_nil
      end
    end
  end
  # ====================================================================
  # CONFIGURATION & CUSTOMIZATION TESTS
  # ====================================================================

  describe "Configuration Options" do
    let(:custom_csp) { "default-src 'none'; script-src 'self'" }

    it "allows overriding the Content-Security-Policy" do
      get "/", {}, "rack.run_once" => true, "rack.input" => ""
      # The app is initialized with options here
      get "/", {}, "rack.run_once" => true, "rack.input" => ""
      
      custom_app = app(content_security_policy: custom_csp)
      custom_app.call({ "PATH_INFO" => "/", "REQUEST_METHOD" => "GET", "rack.input" => StringIO.new, "rack.errors" => StringIO.new })
      
      # We need to re-initialize Rack::Test's `app` method with options for a clean test state
      # The previous `get` call may interfere with the next, so we use a fresh instance.
      response = custom_app.call({ "PATH_INFO" => "/", "REQUEST_METHOD" => "GET", "Content-Type" => "text/html" })
      
      # [status, headers, body]
      headers = response[1]
      expect(headers["content-security-policy"]).to eq(custom_csp)
    end
    
    it "allows overriding a standard default header" do
      # Customize X-Frame-Options
      custom_headers = { "X-Frame-Options" => "SAMEORIGIN" }
      get "/", {}, "rack.run_once" => true, "rack.input" => ""
      
      custom_app = app(custom_headers)
      response = custom_app.call({ "PATH_INFO" => "/", "REQUEST_METHOD" => "GET", "Content-Type" => "text/html" })
      
      headers = response[1]
      expect(headers["x-frame-options"]).to eq("SAMEORIGIN")
      # Ensure other headers are still the default
      expect(headers["x-content-type-options"]).to eq(default_headers["X-Content-Type-Options"])
    end
    
    it "uses the Content-Security-Policy-Report-Only header when configured" do
      get "/", {}, "rack.run_once" => true, "rack.input" => ""
      
      report_only_app = app(report_only: true)
      response = report_only_app.call({ "PATH_INFO" => "/", "REQUEST_METHOD" => "GET", "Content-Type" => "text/html" })
      
      headers = response[1]
      
      # Check for the correct header
      expect(headers["content-security-policy-report-only"]).to eq(default_csp)
      # Ensure the enforcement header is NOT present
      expect(headers["content-security-policy"]).to be_nil
    end
  end

  # ====================================================================
  # DEFAULT POLICY TESTS
  #
  # These pin the hardening decisions behind the defaults, so a future edit
  # cannot quietly reintroduce a broad source or an irreversible commitment.
  # ====================================================================

  describe "Default Policy" do
    let(:hsts) { default_headers["Strict-Transport-Security"] }
    let(:csp_directives) { default_csp.split("; ") }

    describe "Strict-Transport-Security" do
      it "enforces HTTPS for one year including subdomains" do
        expect(hsts).to include("max-age=31536000")
        expect(hsts).to include("includeSubDomains")
      end

      it "does not opt into the browser preload list" do
        # Preload binds the apex domain and every subdomain to HTTPS inside
        # the browser itself and takes months to reverse. It must be an
        # explicit choice, not a side effect of adding a middleware.
        expect(hsts).not_to include("preload")
      end
    end

    describe "Content-Security-Policy" do
      it "is a well-formed directive list with no empty entries or trailing separator" do
        expect(csp_directives).to all(match(/\A[a-z-]+( \S.*)?\z/))
        expect(default_csp).not_to end_with(";")
      end

      it "restricts scripts, styles and fonts to the same origin only" do
        %w[script-src style-src font-src].each do |directive|
          expect(csp_directives).to include("#{directive} 'self'")
        end
      end

      it "does not allow inline styles or scripts" do
        expect(default_csp).not_to include("'unsafe-inline'")
        expect(default_csp).not_to include("'unsafe-eval'")
      end

      it "does not allow arbitrary HTTPS origins" do
        # `https:` as a source lets an attacker who can inject markup load
        # content from any origin they control.
        expect(default_csp).not_to match(/\bhttps:/)
      end

      it "blocks plugins, base tags and framing" do
        expect(csp_directives).to include("object-src 'none'")
        expect(csp_directives).to include("base-uri 'self'")
        expect(csp_directives).to include("frame-ancestors 'none'")
      end

      it "upgrades insecure requests without the deprecated block-all-mixed-content" do
        expect(csp_directives).to include("upgrade-insecure-requests")
        expect(default_csp).not_to include("block-all-mixed-content")
      end
    end

    describe "cross-origin isolation headers" do
      it "sets Cross-Origin-Opener-Policy to same-origin-allow-popups" do
        # Isolates this site from cross-origin openers, but keeps popups the
        # site itself opens (OAuth/OIDC providers in popup mode) working.
        # The stricter "same-origin" would break those out of the box.
        expect(default_headers["Cross-Origin-Opener-Policy"]).to eq("same-origin-allow-popups")
      end

      it "never leaves Cross-Origin-Opener-Policy fully disabled" do
        expect(default_headers["Cross-Origin-Opener-Policy"]).not_to eq("unsafe-none")
      end

      it "sets Cross-Origin-Resource-Policy to same-origin" do
        expect(default_headers["Cross-Origin-Resource-Policy"]).to eq("same-origin")
      end

      it "forbids cross-domain policy files" do
        expect(default_headers["X-Permitted-Cross-Domain-Policies"]).to eq("none")
      end
    end

    describe "Permissions-Policy" do
      let(:policy) { default_headers["Permissions-Policy"] }

      it "denies sensitive device features by default" do
        %w[camera microphone geolocation payment usb].each do |feature|
          expect(policy).to include("#{feature}=()"), "Expected '#{feature}' to be denied"
        end
      end

      it "is a well-formed comma-separated feature list" do
        policy.split(", ").each do |entry|
          expect(entry).to match(/\A[a-z-]+=\(.*\)\z/)
        end
      end
    end
  end

  # ====================================================================
  # OPTION VALIDATION TESTS
  #
  # Every option is validated at construction. A typo or malformed value must
  # raise, not silently weaken the policy or emit a junk header.
  # ====================================================================

  describe "Option Validation" do
    let(:inner) { ->(_env) { [200, { "content-type" => "text/html" }, ["ok"]] } }

    def build(options)
      described_class.new(inner, options)
    end

    it "accepts a well-formed configuration" do
      expect do
        build(
          "X-Frame-Options" => "SAMEORIGIN",
          content_security_policy: "default-src 'self'",
          report_only: true,
          html_only: false,
          path_overrides: { %r{\A/embed/} => { "X-Frame-Options" => "ALLOWALL" } }
        )
      end.not_to raise_error
    end

    it "rejects a non-Hash options argument" do
      expect { build("nope") }.to raise_error(ArgumentError, /must be a Hash/)
    end

    describe "option keys" do
      it "rejects an unknown Symbol option, naming it" do
        expect { build(reprot_only: true) }.to raise_error(ArgumentError, /unknown HeaderGuard option :reprot_only/)
      end

      it "rejects a misspelled report_only rather than silently enforcing the CSP" do
        # The motivating case: a typo here used to emit a junk `report_onlyy`
        # header and *enforce* a CSP the user meant only to report on.
        expect { build(report_onlyy: true) }.to raise_error(ArgumentError)
      end

      it "lists the recognised options in the error" do
        expect { build(bogus: 1) }.to raise_error(ArgumentError, /:content_security_policy, :report_only, :html_only, :path_overrides/)
      end

      it "rejects a key that is neither a String nor a Symbol" do
        expect { build(42 => "x") }.to raise_error(ArgumentError, /unknown HeaderGuard option 42/)
      end
    end

    describe "header names" do
      it "rejects a name containing whitespace" do
        expect { build("X Frame Options" => "DENY") }.to raise_error(ArgumentError, /not a valid HTTP header name/)
      end

      it "rejects a name containing a colon" do
        expect { build("X-Frame-Options:" => "DENY") }.to raise_error(ArgumentError, /not a valid HTTP header name/)
      end

      it "rejects Content-Security-Policy as a raw header, pointing at the option" do
        expect { build("Content-Security-Policy" => "default-src 'none'") }
          .to raise_error(ArgumentError, /use the content_security_policy: and report_only: options/)
      end

      it "rejects Content-Security-Policy-Report-Only as a raw header" do
        expect { build("content-security-policy-report-only" => "x") }.to raise_error(ArgumentError, /cannot be set as a raw header/)
      end
    end

    describe "header values" do
      it "rejects a value containing CRLF, naming response splitting" do
        expect { build("X-Frame-Options" => "DENY\r\nSet-Cookie: pwned=1") }
          .to raise_error(ArgumentError, /control character.*response splitting/)
      end

      it "rejects a value containing a bare LF" do
        expect { build("X-Frame-Options" => "DENY\n") }.to raise_error(ArgumentError, /control character/)
      end

      it "rejects a value containing a NUL byte" do
        expect { build("X-Frame-Options" => "DENY\0") }.to raise_error(ArgumentError, /control character/)
      end

      it "rejects a non-String value" do
        expect { build("X-Frame-Options" => 1) }.to raise_error(ArgumentError, /must be a String, got 1/)
      end

      it "rejects an empty value and suggests nil" do
        # The 0.1.x README recommended "" to disable a header; it emitted a
        # malformed empty header. Fail loudly and point at the right way.
        expect { build("Strict-Transport-Security" => "") }.to raise_error(ArgumentError, /is empty; pass nil to remove/)
      end
    end

    describe "content_security_policy" do
      it "rejects a value containing CRLF" do
        expect { build(content_security_policy: "default-src 'self'\r\nX: y") }.to raise_error(ArgumentError, /control character/)
      end

      it "rejects an empty policy" do
        expect { build(content_security_policy: "") }.to raise_error(ArgumentError, /is empty/)
      end

      it "rejects a non-String, non-boolean value" do
        expect { build(content_security_policy: :strict) }.to raise_error(ArgumentError, /must be a String, false, or nil/)
      end
    end

    describe "flags" do
      it "rejects a non-boolean report_only" do
        expect { build(report_only: "yes") }.to raise_error(ArgumentError, /report_only must be true or false/)
      end

      it "rejects a non-boolean html_only" do
        expect { build(html_only: 1) }.to raise_error(ArgumentError, /html_only must be true or false/)
      end
    end
  end

  # ====================================================================
  # HEADER REMOVAL TESTS
  # ====================================================================

  describe "Removing Headers" do
    let(:env) { Rack::MockRequest.env_for("http://example.com/") }

    def headers_from(options, app_headers = { "content-type" => "text/html" })
      inner = ->(_env) { [200, app_headers, ["ok"]] }
      described_class.new(inner, options).call(env)[1]
    end

    it "does not inject a default header set to nil" do
      headers = headers_from("Strict-Transport-Security" => nil)

      expect(headers).not_to have_key("strict-transport-security")
    end

    it "treats false the same as nil" do
      headers = headers_from("Strict-Transport-Security" => false)

      expect(headers).not_to have_key("strict-transport-security")
    end

    it "matches the header to remove case-insensitively" do
      headers = headers_from("strict-transport-security" => nil)

      expect(headers).not_to have_key("strict-transport-security")
    end

    it "still injects every other default" do
      headers = headers_from("Strict-Transport-Security" => nil)

      expect(headers["x-frame-options"]).to eq(default_headers["X-Frame-Options"])
      expect(headers["content-security-policy"]).to eq(default_csp)
    end

    it "leaves the application's own value untouched for a removed header" do
      # nil means "HeaderGuard does not manage this header", not "strip it".
      headers = headers_from({ "X-Frame-Options" => nil },
                             { "content-type" => "text/html", "x-frame-options" => "SAMEORIGIN" })

      expect(headers["x-frame-options"]).to eq("SAMEORIGIN")
    end

    it "disables CSP with content_security_policy: false" do
      headers = headers_from(content_security_policy: false)

      expect(headers).not_to have_key("content-security-policy")
      expect(headers).not_to have_key("content-security-policy-report-only")
    end

    it "leaves the application's own CSP untouched when disabled" do
      # Lets an app that builds its CSP elsewhere (e.g. the Rails DSL) use
      # HeaderGuard for the other headers only.
      headers = headers_from({ content_security_policy: false },
                             { "content-type" => "text/html", "content-security-policy" => "default-src 'none'" })

      expect(headers["content-security-policy"]).to eq("default-src 'none'")
    end

    it "keeps the default CSP for content_security_policy: nil" do
      # nil must not disable the CSP: `content_security_policy: ENV["CSP"]`
      # with the variable unset would otherwise silently drop it.
      headers = headers_from(content_security_policy: nil)

      expect(headers["content-security-policy"]).to eq(default_csp)
    end
  end

  # ====================================================================
  # PATH OVERRIDE TESTS
  # ====================================================================

  describe "Path Overrides" do
    def headers_at(path, options, app_headers = { "content-type" => "text/html" })
      inner = ->(_env) { [200, app_headers, ["ok"]] }
      env = Rack::MockRequest.env_for("http://example.com#{path}")
      described_class.new(inner, options).call(env)[1]
    end

    let(:auth_relaxed) do
      { path_overrides: { %r{\A/auth/[^/]+/callback\z} => { "Cross-Origin-Opener-Policy" => "unsafe-none" } } }
    end

    describe "matching" do
      it "applies an override whose Regexp matches the path" do
        headers = headers_at("/auth/google/callback", auth_relaxed)

        expect(headers["cross-origin-opener-policy"]).to eq("unsafe-none")
      end

      it "applies the global policy to a path the Regexp does not match" do
        headers = headers_at("/auth/google/callback/extra", auth_relaxed)

        expect(headers["cross-origin-opener-policy"]).to eq(default_headers["Cross-Origin-Opener-Policy"])
      end

      it "matches a String key exactly, not as a prefix" do
        options = { path_overrides: { "/embed" => { "X-Frame-Options" => "SAMEORIGIN" } } }

        expect(headers_at("/embed", options)["x-frame-options"]).to eq("SAMEORIGIN")
        expect(headers_at("/embedded", options)["x-frame-options"]).to eq("DENY")
        expect(headers_at("/embed/", options)["x-frame-options"]).to eq("DENY")
      end

      it "uses the first matching override when several match" do
        options = {
          path_overrides: {
            %r{\A/a} => { "X-Frame-Options" => "SAMEORIGIN" },
            %r{\A/ab} => { "X-Frame-Options" => "ALLOWALL" }
          }
        }

        expect(headers_at("/abc", options)["x-frame-options"]).to eq("SAMEORIGIN")
      end

      it "tolerates a missing PATH_INFO" do
        inner = ->(_env) { [200, { "content-type" => "text/html" }, ["ok"]] }
        headers = described_class.new(inner, auth_relaxed).call({})[1]

        expect(headers["cross-origin-opener-policy"]).to eq(default_headers["Cross-Origin-Opener-Policy"])
      end
    end

    describe "layering" do
      it "inherits every header the override does not mention" do
        headers = headers_at("/auth/google/callback", auth_relaxed)

        expect(headers["strict-transport-security"]).to eq(default_headers["Strict-Transport-Security"])
        expect(headers["x-frame-options"]).to eq(default_headers["X-Frame-Options"])
        expect(headers["content-security-policy"]).to eq(default_csp)
      end

      it "layers on top of global custom headers, not the bare defaults" do
        options = {
          "X-Frame-Options" => "SAMEORIGIN",
          path_overrides: { "/x" => { "Referrer-Policy" => "no-referrer" } }
        }
        headers = headers_at("/x", options)

        expect(headers["x-frame-options"]).to eq("SAMEORIGIN")
        expect(headers["referrer-policy"]).to eq("no-referrer")
      end

      it "can set a different CSP for one path" do
        options = { path_overrides: { "/legacy" => { content_security_policy: "default-src *" } } }

        expect(headers_at("/legacy", options)["content-security-policy"]).to eq("default-src *")
        expect(headers_at("/", options)["content-security-policy"]).to eq(default_csp)
      end

      it "can switch one path to report-only while keeping the global CSP value" do
        options = {
          content_security_policy: "default-src 'self'",
          path_overrides: { "/new" => { report_only: true } }
        }
        headers = headers_at("/new", options)

        expect(headers["content-security-policy-report-only"]).to eq("default-src 'self'")
        expect(headers).not_to have_key("content-security-policy")
      end

      it "can disable CSP for one path only" do
        options = { path_overrides: { "/raw" => { content_security_policy: false } } }

        expect(headers_at("/raw", options)).not_to have_key("content-security-policy")
        expect(headers_at("/", options)["content-security-policy"]).to eq(default_csp)
      end

      it "can remove a header for one path only" do
        options = { path_overrides: { "/widget" => { "X-Frame-Options" => nil } } }

        expect(headers_at("/widget", options)).not_to have_key("x-frame-options")
        expect(headers_at("/", options)["x-frame-options"]).to eq("DENY")
      end

      it "can set html_only for one path" do
        options = { path_overrides: { "/api" => { html_only: true } } }
        headers = headers_at("/api", options, { "content-type" => "application/json" })

        expect(headers).not_to have_key("strict-transport-security")
      end
    end

    describe "validation" do
      let(:inner) { ->(_env) { [200, {}, ["ok"]] } }

      it "rejects Strict-Transport-Security inside an override, explaining why" do
        expect { described_class.new(inner, path_overrides: { "/x" => { "Strict-Transport-Security" => "max-age=0" } }) }
          .to raise_error(ArgumentError, /Strict-Transport-Security cannot be overridden for "\/x": it is host-scoped/)
      end

      it "rejects removing Strict-Transport-Security inside an override too" do
        expect { described_class.new(inner, path_overrides: { "/x" => { "strict-transport-security" => nil } }) }
          .to raise_error(ArgumentError, /host-scoped/)
      end

      it "rejects nested path_overrides" do
        expect { described_class.new(inner, path_overrides: { "/x" => { path_overrides: {} } }) }
          .to raise_error(ArgumentError, /cannot be nested/)
      end

      it "rejects a non-Hash path_overrides" do
        expect { described_class.new(inner, path_overrides: [["/x", {}]]) }
          .to raise_error(ArgumentError, /must be a Hash of path matcher => options/)
      end

      it "rejects a matcher that is neither String nor Regexp" do
        expect { described_class.new(inner, path_overrides: { :auth => {} }) }
          .to raise_error(ArgumentError, /must be a String \(exact path\) or a Regexp, got :auth/)
      end

      it "rejects a non-Hash override value" do
        expect { described_class.new(inner, path_overrides: { "/x" => "unsafe-none" }) }
          .to raise_error(ArgumentError, %r{path_overrides\["/x"\] must be an options Hash})
      end

      it "validates header values inside overrides as strictly as at the top level" do
        expect { described_class.new(inner, path_overrides: { "/x" => { "X-Frame-Options" => "a\r\nb" } }) }
          .to raise_error(ArgumentError, /control character/)
      end

      it "rejects unknown options inside overrides" do
        expect { described_class.new(inner, path_overrides: { "/x" => { reprot_only: true } }) }
          .to raise_error(ArgumentError, /unknown HeaderGuard option :reprot_only/)
      end
    end
  end

  # ====================================================================
  # RACK 3 HEADER CASING
  #
  # The Rack 3 SPEC requires response header keys to be lowercase. An app that
  # returns a plain Hash (rather than a case-insensitive Rack::Headers) must
  # still be detected as HTML and receive every security header.
  # ====================================================================

  describe "Rack 3 header casing" do
    let(:env) { Rack::MockRequest.env_for("http://example.com/") }

    # A SPEC-conformant Rack 3 app: lowercase keys in an ordinary Hash.
    let(:rack3_app) do
      ->(_env) { [200, { "content-type" => "text/html" }, ["<h1>Hello!</h1>"]] }
    end

    # A Rack 2 style app, which conventionally capitalizes its header keys.
    let(:legacy_app) do
      ->(_env) { [200, { "Content-Type" => "text/html" }, ["<h1>Hello!</h1>"]] }
    end

    def headers_from(inner_app, options = {})
      described_class.new(inner_app, options).call(env)[1]
    end

    it "injects every default header when the app uses lowercase keys" do
      headers = headers_from(rack3_app)

      default_headers.each do |header, value|
        expect(headers[header.downcase]).to eq(value), "Expected '#{header.downcase}' to be injected"
      end
    end

    it "injects the CSP when the app uses lowercase keys" do
      expect(headers_from(rack3_app)["content-security-policy"]).to eq(default_csp)
    end

    it "emits only lowercase header keys" do
      keys = headers_from(rack3_app).keys

      expect(keys).to all(match(/\A[^A-Z]*\z/))
    end

    it "still detects HTML from a capitalized Rack 2 Content-Type" do
      headers = headers_from(legacy_app)

      expect(headers["strict-transport-security"]).to eq(default_headers["Strict-Transport-Security"])
    end

    it "does not emit a header twice when the app already set it with different casing" do
      app_with_own_header = lambda do |_env|
        [200, { "content-type" => "text/html", "X-Frame-Options" => "SAMEORIGIN" }, ["<h1>Hello!</h1>"]]
      end

      headers = headers_from(app_with_own_header)

      expect(headers.keys.select { |key| key.downcase == "x-frame-options" }).to eq(["x-frame-options"])
      expect(headers["x-frame-options"]).to eq("DENY")
    end

    it "normalizes a custom header option rather than emitting it alongside the default" do
      headers = headers_from(rack3_app, "X-Frame-Options" => "SAMEORIGIN")

      expect(headers.keys.select { |key| key.downcase == "x-frame-options" }).to eq(["x-frame-options"])
      expect(headers["x-frame-options"]).to eq("SAMEORIGIN")
    end

    it "produces a response that satisfies Rack::Lint" do
      linted = Rack::Lint.new(described_class.new(rack3_app))

      expect { linted.call(env) }.not_to raise_error
    end
  end
end
