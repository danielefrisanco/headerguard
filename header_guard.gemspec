# frozen_string_literal: true

require_relative "lib/header_guard/version"

Gem::Specification.new do |spec|
  spec.name          = "header_guard"
  spec.version       = HeaderGuard::VERSION
  spec.authors       = ["Daniele Frisanco"]
  spec.email         = ["daniele.frisanco@gmail.com"]

  spec.summary       = "A robust Rack middleware for enforcing modern HTTP security headers, including a highly configurable Content Security Policy (CSP)."
  spec.description   = "Designed for applications that require strong browser-side security, HeaderGuard automatically injects HSTS, X-Content-Type-Options, X-Frame-Options, and a customizable CSP. Ideal for SSO and high-security web services."
  spec.homepage      = "https://github.com/danielefrisanco/headerguard"
  spec.license       = "MIT"
  spec.required_ruby_version = ">= 2.6.6"

  spec.metadata["homepage_uri"]    = spec.homepage
  spec.metadata["source_code_uri"] = spec.homepage
  spec.metadata["changelog_uri"]   = "#{spec.homepage}/blob/main/CHANGELOG.md"
  spec.metadata["bug_tracker_uri"] = "#{spec.homepage}/issues"
  # Require multi-factor auth for anyone pushing this gem. A security gem is a
  # high-value target for account takeover; this makes a stolen API key alone
  # insufficient to publish a release.
  spec.metadata["rubygems_mfa_required"] = "true"
  # Specify which files should be added to the gem when it is released.
  spec.files = Dir.chdir(File.expand_path(__dir__)) do
    `git ls-files -z`.split("\x0").reject do |f|
      # Never package build artifacts or internal planning docs. Matching any
      # ".gem" (not just the current version's) keeps a stray local build from
      # being bundled into a release.
      f.end_with?(".gem") ||
        f == "PLAN.md" ||
        f == "Rakefile" ||
        f.match(%r{\A(?:(?:test|spec|features|gemfiles)/|\.(?:git|claude|rspec|travis|circleci)|appveyor)})
    end
  end
  spec.bindir        = "exe"
  spec.executables   = spec.files.grep(%r{\Aexe/}) { |f| File.basename(f) }
  spec.require_paths = ["lib"]

  # Runtime dependencies
  #
  # The middleware calls no Rack API at all -- it only reads and writes the
  # [status, headers, body] triplet -- and handles both Rack 2 (mixed-case) and
  # Rack 3 (lowercase) header conventions, so it works on either major. The
  # upper bound is deliberate: a new Rack major could change the response
  # contract, and this gem should fail to resolve rather than silently inject
  # nothing (which is exactly what happened on Rack 3 before 0.1.2).
  spec.add_runtime_dependency "rack", ">= 2.0", "< 4"

  # Development dependencies
  spec.add_development_dependency "rake", "~> 13.0"
  spec.add_development_dependency "rspec", "~> 3.12"
  spec.add_development_dependency "rack-test", "~> 2.0"
end
