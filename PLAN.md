# HeaderGuard — Remediation Plan

Findings from a review of the gem at v0.1.2 (unreleased). Ordered by priority.
Ship P0 before publishing 0.1.2.

---

## P0 — Critical: gem silently does nothing on conformant Rack 3 apps ✅ DONE (0.1.2)

**Problem.** `lib/header_guard/middleware.rb:37` detects HTML with `headers["Content-Type"]`.
The Rack 3 SPEC requires response header keys to be **lowercase**. An app returning a plain
`{"content-type" => "text/html"}` hash gets **zero** security headers injected — no error,
no warning. Verified against rack 3.2.3.

It only appears to work because apps built on `Rack::Response` return a `Rack::Headers`
(case-insensitive hash), so the lookup happens to succeed. Plain-hash apps — fully legal
Rack 3 — get nothing.

Same root cause, second symptom: the keys written at `middleware.rb:44` are uppercase.
Into a `Rack::Headers` they normalize fine; into a plain hash they leak out uppercase and
violate the SPEC. `Rack::Lint` rejects the response:

    Rack::Lint::LintError: uppercase character in header name: Content-Type

### Tasks
- [x] Downcase all header keys once in `initialize` (defaults + user options + CSP key).
- [x] Make content-type detection case-insensitive: look for `content-type` and fall back to
      `Content-Type` for Rack 2 compatibility.
- [x] Write headers with lowercase keys so plain-hash responses stay SPEC-conformant.
- [x] Regression test: a `MockApp` that returns a **plain hash with lowercase keys**, asserting
      every header is injected.
- [x] Regression test: wrap the stack in `Rack::Lint` and assert it does not raise.

### Resolved in 0.1.2

`lib/header_guard/middleware.rb` now normalizes every header name it owns to lowercase and
reads incoming headers case-insensitively (`fetch_header`), so both Rack 2 and Rack 3 style
responses are detected. `assign` removes any differently-cased duplicate before writing, so
an application that already set `X-Frame-Options` no longer receives the header twice — a
duplication bug found while fixing this. Custom header options are normalized too, so
`"x-frame-options" => "SAMEORIGIN"` overrides the default instead of appending to it.

Seven regression tests were added under `Rack 3 header casing` in
`spec/header_guard/middleware_spec.rb`, including a plain-lowercase-Hash app, a duplicate
suppression case, and a `Rack::Lint` assertion. Five pre-existing assertions that inspected
the raw headers Hash by capitalized key were updated to lowercase — they had been encoding
the buggy behaviour. Suite: 17 examples, 0 failures.

---

## P1 — Injection scope is too narrow for a security gem ✅ DONE (0.2.0)

**Problem.** Headers are applied only to `2xx && text/html` (`middleware.rb:37`), which excludes
the responses that need them most:

- **Error pages (4xx/5xx) get no CSP.** Error pages routinely reflect user input and are a
  classic XSS surface — the last place CSP should be off.
- **JSON/API responses get no `X-Content-Type-Options: nosniff`.** Sniffing protection on JSON
  is precisely the point of that header.
- **HSTS is skipped on redirects**, but the HTTP→HTTPS redirect is the response where HSTS
  matters most.

### Tasks
- [x] Apply `Strict-Transport-Security`, `X-Content-Type-Options`, `Referrer-Policy` and
      `X-Frame-Options` **unconditionally**, on every status and content type.
- [x] Keep CSP scoped to HTML, but extend it to all statuses (not just 2xx) so error pages
      are covered.
- [x] Add an escape hatch for the old narrow behaviour — shipped as `html_only: true`.
- [x] Tests for: 500 HTML page (CSP present), JSON 200 (nosniff present, CSP absent),
      302 redirect (HSTS present).
- [x] Replace the no-op test at `spec/header_guard/middleware_spec.rb:90-109` — it builds an
      app, calls it, discards the result, and the comment admits it tests nothing.

### Resolved in 0.2.0

`call` now decides scope with two predicates: `apply_standard_headers?` (always, unless
`html_only`) and `apply_csp?` (any HTML response, unless `html_only`). `application/xhtml+xml`
is treated as HTML alongside `text/html`. The old "Exclusion Logic" spec section — whose
assertions encoded the narrow behaviour — was replaced with a "Response Scope" section of
twelve tests covering JSON 200, 302, 204 with no content-type, HTML 500, HTML 404, JSON 404,
XHTML, report-only on error pages, and the four `html_only` legacy cases. Dead `/json` and
`/redirect` routes were removed from the spec's `MockApp`. README "How It Works" rewritten.
Suite: 26 examples, 0 failures.

---

## P2 — Default policy hardening ✅ DONE (0.2.0)

- [x] **Drop `preload` from the default HSTS** — done. Default is now
      `max-age=31536000; includeSubDomains`; README documents `preload` as an explicit opt-in
      with a link to hstspreload.org.
- [x] **Remove `block-all-mixed-content`** — done. `upgrade-insecure-requests` remains.
- [x] **Tighten `style-src`** — done, now `'self'`. README documents `'unsafe-inline'` as a
      deliberate opt-in and steers toward nonces.
- [x] Narrow `font-src` — done, now `'self'`.
- [x] **Add modern headers** — done, all four:
      - `Cross-Origin-Opener-Policy: same-origin-allow-popups` — chosen over `same-origin`
        after discussion: the gem targets SSO apps where popup-based client SDKs are common,
        and `allow-popups` still blocks anyone from opening *this* site and keeping a
        handle. README documents `unsafe-none` for identity providers (you *are* the popup)
        and `same-origin` for the strictest isolation. Per-path overrides, which would let
        an IdP relax only its popup page, are deferred to 0.3.0 alongside P3 — see the note
        under P3.
      - `Cross-Origin-Resource-Policy: same-origin`
      - `X-Permitted-Cross-Domain-Policies: none`
      - `Permissions-Policy: accelerometer=(), camera=(), geolocation=(), gyroscope=(),
        magnetometer=(), microphone=(), payment=(), usb=()`

### Resolved in 0.2.0

`lib/header_guard.rb` rewritten: `DEFAULT_HEADERS` grows from four to eight entries, each
with a comment explaining the choice and, where the value can break something, the
override to use. `DEFAULT_CSP` is built from an array joined with `"; "`, so each directive
is on its own line. Thirteen "Default Policy" tests pin every decision — no `preload`, no
`'unsafe-inline'`, no `https:`, no `block-all-mixed-content`, each new header's value, and
well-formedness of both the CSP and the Permissions-Policy. README header table updated to
eight rows, with sections on HSTS preload, COOP and popup auth, and CORP and embedded
assets. CHANGELOG carries a detailed "Upgrading from 0.1.x" list. Suite: 39 examples, 0
failures.

---

## P3 — Configuration API correctness ✅ DONE (0.3.0)

- [x] **Validate options** — done. Unknown Symbol keys, non-token header names, non-String /
      empty values, non-boolean flags, and the CSP given as a raw header all raise
      `ArgumentError` at construction with a message naming the offender and, for the CSP
      case, pointing at the right option.
- [x] **Reject CRLF in header values** — done, broadened to every control character
      (`[\x00-\x1F\x7F]`), for header values and the CSP alike.
- [x] **Support removing a default header** — done. `nil` or `false` means "HeaderGuard does
      not manage this header": nothing injected, the app's own value passes through. README dev
      example fixed. `""` is now rejected with a message pointing at `nil`.
      Also: `content_security_policy: false` disables the CSP (for apps using the Rails DSL);
      `nil` deliberately keeps the default so an unset ENV var can't drop it.
- [ ] Consider a structured CSP builder (hash of directive => sources) instead of raw strings,
      so directives can be merged rather than wholesale replaced. **Deferred** — a larger API
      design question; the raw-string approach with per-path overrides covers the immediate
      cases.
- [x] **Path-scoped overrides** — done as `path_overrides:`. `Regexp` matches the path, `String`
      matches exactly, first match wins; value is a nested options hash layered over the global
      policy. `Strict-Transport-Security` is refused inside an override (host-scoped), as is
      nesting. Every value inside an override is validated as strictly as at the top level.

### Resolved in 0.3.0

`middleware.rb` now resolves configuration into `Policy` structs — one global, one per path
override — via a single `build_policy(options, base)` that layers an options hash over a base.
The same function handles the top level (over the defaults) and each override (over the global
policy), so overrides inherit everything they don't mention and are validated identically.
`call` selects the policy by `PATH_INFO`, then applies it as before. 48 new tests across
"Option Validation", "Removing Headers" and "Path Overrides". README gains sections 5–7
(removing headers, per-path overrides, validation). Suite: 88 examples, 0 failures.

---

## P4 — Packaging and supply chain ✅ DONE (0.3.1)

- [x] **Delete the committed `.gem` artifacts** — done in 0.1.2. Untracked via
      `git rm --cached` (kept on disk locally). The gemspec now rejects any file ending in
      `.gem` rather than only the current version's name, so a stray local build cannot be
      bundled into a release. `PLAN.md` is excluded from the package too.
- [x] **Add `.gitignore`** — done in 0.1.2: `*.gem`, `/pkg/`, `/.bundle/`, `/coverage/`,
      `/tmp/`, `/doc/`, `/.yardoc`. `Gemfile.lock` left tracked, as it has been historically.
- [x] **Add `rubygems_mfa_required` to gemspec metadata** — done in 0.3.1. Note: the
      RubyGems account doing `gem push` must have MFA enabled or the push is rejected.
- [x] Add `source_code_uri` and `changelog_uri` metadata — done in 0.3.1, plus
      `homepage_uri` and `bug_tracker_uri`.
- [x] **Relax the rack pin.** Done in 0.3.1 as `>= 2.0, < 4`. Verified, not assumed: the
      full suite (88 examples, including the `Rack::Lint` case) passes under Rack 2.2.24,
      where `Rack::Headers` does not even exist — confirming the middleware calls no Rack
      API and only handles the response triplet. The `< 4` bound is deliberate (see the
      gemspec comment): fail to resolve on an unverified major rather than silently inject
      nothing, which is what P0 was. The `rack-test` dev dependency was bounded to `~> 2.0`
      to silence the open-ended-dependency build warning.

### Resolved in 0.3.1

Gemspec only, no code changes. The Rack 2 run was done by hand with a scratch Gemfile
pinning `rack ~> 2.2`; making it repeatable is the CI matrix in P5, which should also add a
`RACK_VERSION` switch to the project Gemfile.

---

## P5 — Project hygiene

- [ ] Add `CHANGELOG.md` — 0.1.2 is bumped in the working tree with no record of what changed.
- [ ] Add CI (GitHub Actions): run RSpec against Ruby 3.x and both Rack 2 and Rack 3.
- [ ] Add a `Rakefile` with a default `spec` task.
- [ ] Add `spec/spec_helper.rb` and `.rspec`.
- [ ] Fix the gemspec author list (`header_guard.gemspec:8` credits "Gemini AI").
- [ ] README: fix the broken nested markdown link at line 106
      (`[https://trusted.cdn.com](https://trusted.cdn.com)` inside a code block).

---

## Suggested release sequencing

1. ~~**0.1.2** — P0 only (the Rack 3 fix) plus its regression tests.~~ **Done.** Patch bump,
   per semver: a bug fix restoring documented behaviour, no API additions.
2. **0.2.0** — P1 ✅ + P2 ✅ done, ready to release. These change which headers appear on
   which responses and what the defaults are, so they are breaking-ish and got a minor bump
   and a detailed upgrade section in the CHANGELOG.
3. **0.3.0** — P3 ✅ done. Additive (validation, `nil` removal, `path_overrides`), but
   previously-accepted-yet-wrong configurations now raise at boot, so a minor bump.
4. **0.3.1** — P4 ✅ done. Packaging only; patch bump. Widening the Rack constraint adds
   no API and changes no behaviour, and `rubygems_mfa_required` affects only the publisher.
5. P5 needs no gem release of its own — CI, Rakefile and spec scaffolding are not shipped in
   the package. Only the gemspec author fix and the README link would reach users.
