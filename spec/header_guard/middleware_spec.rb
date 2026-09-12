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
