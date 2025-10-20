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

Any key/value pair passed to the middleware that matches a standard header will override the default value.

| Header | Default Value | Purpose | 
 | ----- | ----- | ----- | 
| `Strict-Transport-Security` | `max-age=31536000; includeSubDomains; preload` | Enforces HTTPS usage. | 
| `X-Content-Type-Options` | `nosniff` | Prevents browser MIME-sniffing. | 
| `X-Frame-Options` | `DENY` | Prevents clickjacking (set to SAMEORIGIN to allow framing on the same site). | 
| `Referrer-Policy` | `strict-origin-when-cross-origin` | Controls referrer information sent with requests. | 

**Example: Overriding X-Frame-Options and Referrer-Policy:**
```ruby
# In a Rails initializer or config.ru
config.middleware.use HeaderGuard::Middleware, 
  "X-Frame-Options" => "SAMEORIGIN",
  "Referrer-Policy" => "no-referrer"
```
#### 2\. Custom Content Security Policy (CSP)

You can define a custom CSP string to replace the secure default provided by HeaderGuard.

```ruby
custom_csp = "default-src 'self'; script-src 'self' [https://trusted.cdn.com](https://trusted.cdn.com);"
use HeaderGuard::Middleware, content_security_policy: custom_csp

```
#### 3\. Report-Only Mode

To test a new CSP without enforcing it, set the report\_only option to true. This will use the Content-Security-Policy-Report-Only header instead of the standard Content-Security-Policy header.

```ruby
# The browser will report violations but will not block resources.
config.middleware.use HeaderGuard::Middleware, report_only: true

```

How It Works
------------

HeaderGuard hooks into the Rack request lifecycle and performs the following actions on responses with a 2xx status code and a Content-Type of text/html:

1.  **Header Merging:** It takes the default security headers and merges them with any custom headers supplied during initialization, ensuring user configuration takes precedence.
    
2.  **Injection:** It injects the final set of standard security headers.
    
3.  **CSP Injection:** It injects the configured Content Security Policy, using either the standard enforcement header or the Report-Only header.
    

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