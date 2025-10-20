# frozen_string_literal: true

require_relative "lib/header_guard/version"

Gem::Specification.new do |spec|
  spec.name          = "header_guard"
  spec.version       = HeaderGuard::VERSION
  spec.authors       = ["Gemini AI", "Daniele Frisanco"]
  spec.email         = ["daniele.frisanco@gmail.com"]

  spec.summary       = "A robust Rack middleware for enforcing modern HTTP security headers, including a highly configurable Content Security Policy (CSP)."
  spec.description   = "Designed for applications that require strong browser-side security, HeaderGuard automatically injects HSTS, X-Content-Type-Options, X-Frame-Options, and a customizable CSP. Ideal for SSO and high-security web services."
  spec.homepage      = "https://github.com/placeholder/header_guard"
  spec.license       = "MIT"
  spec.required_ruby_version = ">= 2.6.6" 
  # Specify which files should be added to the gem when it is released.
  spec.files = Dir.chdir(File.expand_path(__dir__)) do
    `git ls-files -z`.split("\x0").reject do |f|
      (f == spec.full_name + ".gem") ||
        f.match(%r{\A(?:(?:test|spec|features)/|\.(?:git|travis|circleci)|appveyor)})
    end
  end
  spec.bindir        = "exe"
  spec.executables   = spec.files.grep(%r{\Aexe/}) { |f| File.basename(f) }
  spec.require_paths = ["lib"]

  # Runtime dependencies
  spec.add_runtime_dependency "rack", "~> 3.0"

  # Development dependencies
  spec.add_development_dependency "rspec", "~> 3.12"
  spec.add_development_dependency "rack-test"
end
