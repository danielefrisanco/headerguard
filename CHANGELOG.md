# Changelog

All notable changes to this project are documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

Targeting 0.2.0. See `PLAN.md` for the remaining remediation work (P2–P5).

### Changed

- **Standard headers are now applied to every response.** `Strict-Transport-Security`,
  `X-Content-Type-Options`, `X-Frame-Options` and `Referrer-Policy` were previously
  injected only on 2xx responses with an HTML content type, which excluded the responses
  that need them most: JSON bodies got no `nosniff`, and the HTTP→HTTPS redirect — the
  response where HSTS matters — got no HSTS. They now go on every response regardless
  of status code or content type.

- **The Content Security Policy is now applied to HTML responses of every status.**
  Previously only 2xx HTML responses received a CSP, leaving 4xx/5xx error pages
  unprotected. Error pages routinely reflect user input and are a classic XSS surface.
  CSP remains restricted to HTML content types, as it governs documents only.

- `application/xhtml+xml` is now treated as HTML for CSP purposes alongside `text/html`.

- **`preload` removed from the default `Strict-Transport-Security`.** Preload is the
  opt-in signal for the browser HSTS preload list, which hard-codes the apex domain and
  every subdomain as HTTPS-only inside the browser itself; removal takes months. That is
  a commitment to make explicitly, not one to acquire by adding a middleware. The default
  is now `max-age=31536000; includeSubDomains`. Opt back in by overriding the header.

- **Default CSP tightened to a strict same-origin baseline.** `style-src` was
  `'self' 'unsafe-inline' https:` and `font-src` was `'self' https: data:`. Both are now
  `'self'`. `https:` as a source allows content from any HTTPS origin and `'unsafe-inline'`
  allows arbitrary inline styles — either lets an attacker who can inject markup load or
  run content of their choosing, which is a weak default for something billed as a secure
  baseline. Applications that need inline styles should add `'unsafe-inline'` deliberately
  via `content_security_policy:`.

- Default CSP directives are now separated by `"; "` rather than `";"` for readability.
  Semantically identical.

### Added

- `html_only: true` option, which restores the 0.1.x behaviour of injecting nothing
  unless the response is a 2xx with an HTML content type. This is a migration aid for
  applications that depended on the narrower scope, not a recommended configuration.

- **Four new default headers:**
  - `Cross-Origin-Opener-Policy: same-origin` — isolates the browsing context from
    cross-origin windows, mitigating XS-Leaks and Spectre-class attacks.
  - `Cross-Origin-Resource-Policy: same-origin` — stops other origins embedding this
    site's resources via no-cors requests.
  - `X-Permitted-Cross-Domain-Policies: none` — forbids Flash/Acrobat cross-domain
    policy files.
  - `Permissions-Policy` — denies `accelerometer`, `camera`, `geolocation`, `gyroscope`,
    `magnetometer`, `microphone`, `payment` and `usb` unless explicitly enabled.

### Removed

- `block-all-mixed-content` from the default CSP. The directive is deprecated and was
  removed from CSP Level 3; `upgrade-insecure-requests`, which remains, covers it.

### Upgrading from 0.1.x

Read this section before deploying — 0.2.0 tightens several defaults and some
applications will need to opt back into behaviour they relied on.

- **Standard headers now land on every response.** If your application sets its own
  value for one of them on a non-HTML response (for example a different
  `X-Frame-Options` on an API endpoint), HeaderGuard now overwrites it there too, as it
  always has on HTML. Pass the desired value as a custom header option, or use
  `html_only: true` while you migrate.
- **Inline styles are now blocked by the default CSP.** If your pages use inline
  `<style>` or `style=""` attributes (CSS-in-JS libraries commonly do), pass a
  `content_security_policy:` that adds `'unsafe-inline'` to `style-src`, or better, move
  to nonces.
- **Third-party fonts and stylesheets are now blocked by the default CSP.** Add the
  specific origins you use (e.g. `https://fonts.googleapis.com`) to `style-src` and
  `font-src` rather than reinstating `https:`.
- **Popup-based OAuth/OIDC flows will break under the new `Cross-Origin-Opener-Policy`.**
  `same-origin` severs `window.opener` across origins. Redirect-based flows are
  unaffected. If your site *opens* the popup, override with `same-origin-allow-popups`;
  if your site *is* the popup (you are the identity provider), override with
  `unsafe-none`.
- **Assets embedded by other sites will be blocked by `Cross-Origin-Resource-Policy`.**
  If your app serves images, scripts or fonts meant to load on other origins, override
  with `cross-origin`.
- **Features denied by `Permissions-Policy`** (camera, microphone, geolocation, payment,
  and so on) must be re-enabled explicitly if your app uses them.
- **HSTS preload is no longer set.** If you had already submitted your domain to the
  preload list, add `preload` back via a custom header — otherwise the list's periodic
  checks will flag the domain for removal.

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

- **Previously released `.gem` files are no longer packaged inside new releases.**
  `header_guard-0.1.0.gem` and `header_guard-0.1.1.gem` were tracked in git, and the
  gemspec filtered only the *current* version's file, so each release bundled every
  earlier one — 0.1.1 was 16KB largely because it contained 0.1.0. The artifacts are now
  untracked and gitignored, and the gemspec rejects any `.gem` file rather than one
  specific name. `PLAN.md` is excluded from the package as well.

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
