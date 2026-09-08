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

## P1 — Injection scope is too narrow for a security gem

**Problem.** Headers are applied only to `2xx && text/html` (`middleware.rb:37`), which excludes
the responses that need them most:

- **Error pages (4xx/5xx) get no CSP.** Error pages routinely reflect user input and are a
  classic XSS surface — the last place CSP should be off.
- **JSON/API responses get no `X-Content-Type-Options: nosniff`.** Sniffing protection on JSON
  is precisely the point of that header.
- **HSTS is skipped on redirects**, but the HTTP→HTTPS redirect is the response where HSTS
  matters most.

### Tasks
- [ ] Apply `Strict-Transport-Security`, `X-Content-Type-Options`, `Referrer-Policy` and
      `X-Frame-Options` **unconditionally**, on every status and content type.
- [ ] Keep CSP scoped to HTML, but extend it to all statuses (not just 2xx) so error pages
      are covered.
- [ ] Add a `:html_only_headers` / `:apply_to` escape hatch if any consumer needs the old
      narrow behaviour.
- [ ] Tests for: 500 HTML page (CSP present), JSON 200 (nosniff present, CSP absent),
      302 redirect (HSTS present).
- [ ] Replace the no-op test at `spec/header_guard/middleware_spec.rb:90-109` — it builds an
      app, calls it, discards the result, and the comment admits it tests nothing.

---

## P2 — Default policy hardening

- [ ] **Drop `preload` from the default HSTS** (`lib/header_guard.rb:11`). Preload is an opt-in
      commitment binding the apex domain *and all subdomains* to HTTPS, and removal from the
      list takes months. Too sharp to acquire merely by adding the middleware. Keep
      `max-age=31536000; includeSubDomains`; document `preload` as an explicit opt-in.
- [ ] **Remove `block-all-mixed-content`** (`lib/header_guard.rb:39`) — deprecated and removed
      from CSP3; `upgrade-insecure-requests` already covers it.
- [ ] **Tighten `style-src`** (`lib/header_guard.rb:37`). `'self' 'unsafe-inline' https:` allows
      inline styles plus any HTTPS origin, enabling CSS-based injection and data exfiltration —
      weak for something billed as a "secure baseline". Consider `'self'` with `'unsafe-inline'`
      documented as an opt-in.
- [ ] Narrow `font-src 'self' https: data:` for the same reason.
- [ ] **Add modern headers** to the defaults:
      - `Cross-Origin-Opener-Policy: same-origin`
      - `Cross-Origin-Resource-Policy: same-origin`
      - `X-Permitted-Cross-Domain-Policies: none`
      - `Permissions-Policy` (a conservative deny list)

---

## P3 — Configuration API correctness

- [ ] **Validate options** (`middleware.rb:24`). Unknown keys become header names verbatim, so a
      typo like `report_onlyy: true` silently *enforces* a CSP the user meant to only report on,
      and emits a junk `report_onlyy` header. Raise `ArgumentError` on unrecognised symbol keys;
      treat only strings as custom headers.
- [ ] **Reject CRLF in header values.** A CSP `report-uri` built from ENV containing `\r\n`
      gives response splitting. Validate on init and raise.
- [ ] **Support removing a default header.** README currently suggests
      `header_options["Strict-Transport-Security"] = ""`, which emits an empty header rather
      than omitting it. Make `nil` delete the header, and fix the README example.
- [ ] Consider a structured CSP builder (hash of directive => sources) instead of raw strings,
      so directives can be merged rather than wholesale replaced.

---

## P4 — Packaging and supply chain

- [ ] **Delete the committed `.gem` artifacts** (`header_guard-0.1.0.gem`,
      `header_guard-0.1.1.gem`). They are tracked in git and ship *inside* each new release —
      the gemspec rejects only the current version's file. It compounds: 0.1.0 is 9KB, 0.1.1 is
      16KB because it already contains 0.1.0.
- [ ] **Add `.gitignore`** (none exists): `*.gem`, `/pkg/`, `/.bundle/`, `Gemfile.lock` if
      preferred for a library.
- [ ] **Add `rubygems_mfa_required` to gemspec metadata** — standard for any published gem,
      doubly so for a security gem.
- [ ] Add `source_code_uri` and `changelog_uri` metadata.
- [ ] **Relax the rack pin.** `rack ~> 3.0` locks out Rack 2 and older Rails; once casing is
      handled correctly, `>= 2.0` supports both.

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
2. **0.2.0** — P1 + P2. These change which headers appear on which responses, so they are
   breaking-ish and deserve a minor bump and CHANGELOG notes.
3. **0.3.0** — P3 API work.
4. P4/P5 can land alongside any of the above.
