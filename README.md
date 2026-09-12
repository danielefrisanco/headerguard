HeaderGuard
===========

A robust and simple-to-use Rack middleware for enforcing modern HTTP security headers, including a highly configurable Content Security Policy (CSP).

HeaderGuard is designed to automatically inject essential security headers like HSTS, X-Content-Type-Options, X-Frame-Options, and a customizable Content Security Policy, making your application significantly more resilient against XSS, clickjacking, and other common attacks.

Installation
------------

Add this line to your application's Gemfile:

```ruby
gem 'header_guard'
```
And then execute:

```bash
$ bundle install

```
Usage
-----

### Basic Setup (Recommended)

To enable all default, secure headers, simply include the middleware in your Rack application (e.g., in a Rails config/application.rb or a Rack config.ru).

**For Rails (in `config/application.rb`:**

```ruby
config.middleware.use HeaderGuard::Middleware
```
**For generic Rack apps (in config.ru):**

```ruby
require 'header_guard'
use HeaderGuard::Middleware
run YourApp.new
```
#### Environment-Specific Configuration (Development & Testing)
For local development and testing, you often need to disable the strictest headers, like HSTS (which forces HTTPS) or the CSP (which can block inline scripts for tools).
#### A. Disabling Headers in Development
The simplest approach is to conditionally skip the middleware based on the Rails/Rack environment.

**For Rails (in `config/application.rb`):**
```ruby
unless Rails.env.development? || Rails.env.test?
  config.middleware.use HeaderGuard::Middleware
end

```
#### B. Relaxing Specific Headers for Development

If you only want to relax one or two headers (like HSTS) but keep the others, you can conditionally override the configuration.

**For Rails (in an initializer like `config/initializers/header_guard.rb`):**
```ruby
# Start with an empty configuration hash
header_options = {}

if Rails.env.development? || Rails.env.test?
  # 1. Disable Strict-Transport-Security for local HTTP development
  header_options["Strict-Transport-Security"] = ""
  
  # 2. Relax CSP to allow development tools that rely on 'unsafe-inline' scripts/styles
  # NOTE: The HeaderGuard default CSP uses 'script-src "self"'. This adds the required dev overrides.
  dev_csp = "script-src 'self' 'unsafe-inline' 'unsafe-eval'; style-src 'self' 'unsafe-inline';"
  header_options[:content_security_policy] = dev_csp
end

# Apply the middleware with the environment-specific configuration
Rails.application.config.middleware.use HeaderGuard::Middleware, header_options

```



### Configuration Options for Customization

When integrating `HeaderGuard` into your project, you can pass an options hash to the middleware to customize or override any of the default security settings.

#### 1\. Overriding Standard Headers

Any key/value pair passed to the middleware that matches a standard header will override the default value. Header names are matched case-insensitively.

| Header | Default Value | Purpose |
| ----- | ----- | ----- |
| `Strict-Transport-Security` | `max-age=31536000; includeSubDomains` | Enforces HTTPS usage. |
| `X-Content-Type-Options` | `nosniff` | Prevents browser MIME-sniffing. |
| `X-Frame-Options` | `DENY` | Prevents clickjacking (set to `SAMEORIGIN` to allow framing on the same site). |
| `Referrer-Policy` | `strict-origin-when-cross-origin` | Controls referrer information sent with requests. |
| `Cross-Origin-Opener-Policy` | `same-origin-allow-popups` | Isolates the browsing context from cross-origin openers (XS-Leaks, Spectre) while allowing popups you open. |
| `Cross-Origin-Resource-Policy` | `same-origin` | Stops other origins embedding your resources via no-cors requests. |
| `X-Permitted-Cross-Domain-Policies` | `none` | Forbids Flash/Acrobat cross-domain policy files. |
| `Permissions-Policy` | `accelerometer=(), camera=(), geolocation=(), gyroscope=(), magnetometer=(), microphone=(), payment=(), usb=()` | Denies sensitive device features unless enabled. |

**Example: Overriding X-Frame-Options and Referrer-Policy:**
```ruby
# In a Rails initializer or config.ru
config.middleware.use HeaderGuard::Middleware, 
  "X-Frame-Options" => "SAMEORIGIN",
  "Referrer-Policy" => "no-referrer"
```

**Opting into HSTS preload.** The default deliberately omits `preload`. It is the signal for the [browser HSTS preload list](https://hstspreload.org/), which hard-codes your apex domain *and every subdomain* as HTTPS-only inside the browser, and removal takes months. Add it only once you've confirmed every subdomain serves HTTPS:

```ruby
config.middleware.use HeaderGuard::Middleware,
  "Strict-Transport-Security" => "max-age=31536000; includeSubDomains; preload"
```

**`Cross-Origin-Opener-Policy` and popup-based auth.** The default `same-origin-allow-popups` means no cross-origin page can open your site and keep a handle on it, while popups *your* site opens — an OAuth/OIDC provider in popup mode — can still talk back via `window.opener`. Redirect-based flows are unaffected either way.

Two situations need a different value:

```ruby
# Your site *is* the popup (you are the identity provider): the page the client
# opens must keep window.opener, which requires disabling isolation on it.
config.middleware.use HeaderGuard::Middleware, "Cross-Origin-Opener-Policy" => "unsafe-none"

# You open no popups and want the strictest isolation available (also the
# value required, together with COEP, for cross-origin isolated features such
# as SharedArrayBuffer):
config.middleware.use HeaderGuard::Middleware, "Cross-Origin-Opener-Policy" => "same-origin"
```

**Assets embedded by other sites and `Cross-Origin-Resource-Policy`.** `same-origin` prevents other origins from loading your images, scripts or fonts. If your app serves assets meant to be embedded elsewhere, set it to `cross-origin`.
#### 2\. Custom Content Security Policy (CSP)

The default CSP is a strict same-origin baseline:

```
default-src 'self'; base-uri 'self'; font-src 'self'; form-action 'self';
frame-ancestors 'none'; object-src 'none'; script-src 'self'; style-src 'self';
upgrade-insecure-requests
```

Resources may load only from your own origin; plugins, `<base>` tags and object embeds are blocked; inline scripts and styles are not permitted. Most real applications will need to extend this. You can define a custom CSP string to replace the default:

```ruby
custom_csp = "default-src 'self'; script-src 'self' https://trusted.cdn.com;"
use HeaderGuard::Middleware, content_security_policy: custom_csp

```

When extending the policy, add the specific origins you need rather than broad sources. `https:` as a source allows content from *any* HTTPS origin, and `'unsafe-inline'` allows any inline style or script — both let an attacker who can inject markup load or run content of their choosing. If you must allow inline styles (many CSS-in-JS libraries need it), do so knowingly:

```ruby
# Allowing inline styles, explicitly.
use HeaderGuard::Middleware,
  content_security_policy: "default-src 'self'; script-src 'self'; style-src 'self' 'unsafe-inline'; object-src 'none'; frame-ancestors 'none'"

```
#### 3\. Report-Only Mode

To test a new CSP without enforcing it, set the report\_only option to true. This will use the Content-Security-Policy-Report-Only header instead of the standard Content-Security-Policy header.

```ruby
# The browser will report violations but will not block resources.
config.middleware.use HeaderGuard::Middleware, report_only: true

```
#### 4\. Restricting to HTML Responses (legacy behaviour)

By default HeaderGuard applies its standard headers to **every** response and the CSP to every **HTML** response, whatever the status code (see *How It Works* below). Versions before 0.2.0 injected nothing unless the response was a 2xx with an HTML content type. If you depend on that narrower behaviour, set `html_only`:

```ruby
# 0.1.x behaviour: inject only on 2xx text/html responses.
config.middleware.use HeaderGuard::Middleware, html_only: true

```
This is a migration aid, not a recommended configuration: it leaves JSON responses without `X-Content-Type-Options`, redirects without HSTS, and error pages without a CSP.

How It Works
------------

HeaderGuard hooks into the Rack request lifecycle and, on every response passing through it:

1.  **Header Merging:** It takes the default security headers and merges them with any custom headers supplied during initialization, ensuring user configuration takes precedence.
    
2.  **Standard Header Injection:** It injects every header in the table above (HSTS, `X-Content-Type-Options`, `X-Frame-Options`, `Referrer-Policy`, the cross-origin isolation headers and `Permissions-Policy`) on **every** response, regardless of status code or content type. HSTS matters most on the HTTP→HTTPS redirect, and `nosniff` exists precisely to protect non-HTML bodies such as JSON.
    
3.  **CSP Injection:** It injects the configured Content Security Policy — using either the standard enforcement header or the Report-Only header — on every response whose `Content-Type` is `text/html` or `application/xhtml+xml`, **including error pages**. Error pages routinely reflect user input and are a classic XSS surface, so they need a policy at least as much as a 200 does. Non-HTML responses do not receive a CSP, as it governs documents only.
    
Header names are handled case-insensitively and always written in lowercase, as the Rack 3 SPEC requires, so both Rack 2 and Rack 3 style applications are supported.

Development
-----------

After checking out the repository, run bundle install to install dependencies. Then, run rspec to execute the tests.
This gem uses RSpec and Rack::Test for its testing suite.
#### Prerequisites
To set up the development environment, you will need:
Ruby (version 2.6.6 or higher, as defined in the .gemspec)

Bundler
#### Setup and Testing
1. Clone the repository:

```bash
git clone https://github.com/danielefrisanco/headerguard
cd header_guard
```

2. Install all development and testing dependencies:

```bash
bundle install
```

3. Run the test suite using RSpec:

```bash
bundle exec rspec
```

(This ensures all tests, including the critical configuration override tests, are passing.)

Contributing
------------

Bug reports and pull requests are welcome on GitHub at [https://github.com/danielefrisanco/headerguard](https://github.com/danielefrisanco/headerguard).