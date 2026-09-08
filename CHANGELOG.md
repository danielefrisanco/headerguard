# Changelog

All notable changes to this project are documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

See `PLAN.md` for the remaining remediation work (P1–P5), targeted at 0.2.0.

## [0.1.2] - 2026-09-08

### Fixed

- **Security headers were silently not injected on conformant Rack 3 applications.**
  The HTML check read `headers["Content-Type"]`, but the Rack 3 SPEC requires response
  header keys to be lowercase. An application returning a plain Hash such as
  `{"content-type" => "text/html"}` received **no** security headers at all — no HSTS,
  no CSP, no `nosniff` — with no error raised. The gem only appeared to work for
  applications built on `Rack::Response`, which returns a case-insensitive
  `Rack::Headers`. Header lookup is now case-insensitive, so both Rack 2 and Rack 3
  style responses are detected.

- **Emitted header names violated the Rack 3 SPEC.** Headers were written with
  capitalized keys (`Strict-Transport-Security`), which `Rack::Lint` rejects with
  `uppercase character in header name`. All injected headers are now written in
  lowercase.

- **A header set by the application under a different capitalization is no longer
  duplicated.** Previously an app setting `X-Frame-Options` would end up with both its
  own key and the middleware's, sending the header twice. Differently-cased duplicates
  are removed before the middleware writes its value.

- **A custom header option now overrides the matching default regardless of case.**
  Passing `"x-frame-options" => "SAMEORIGIN"` previously appended a second header
  instead of replacing the default.

### Changed

- Injected response header names are now lowercase. This is invisible over HTTP, where
  header names are case-insensitive, but code inspecting the raw Rack headers Hash by an
  exact capitalized key needs to be updated. `Rack::Headers` and `Rack::Test` lookups are
  unaffected.

## [0.1.1] - 2025-10-20

### Fixed

- Corrected the `homepage` metadata in the gemspec.

## [0.1.0] - 2025-10-20

### Added

- Initial release: Rack middleware injecting HSTS, `X-Content-Type-Options`,
  `X-Frame-Options`, `Referrer-Policy` and a configurable Content Security Policy,
  with `report_only` support.

[Unreleased]: https://github.com/danielefrisanco/headerguard/compare/v0.1.2...HEAD
[0.1.2]: https://github.com/danielefrisanco/headerguard/compare/v0.1.1...v0.1.2
[0.1.1]: https://github.com/danielefrisanco/headerguard/compare/v0.1.0...v0.1.1
[0.1.0]: https://github.com/danielefrisanco/headerguard/releases/tag/v0.1.0
