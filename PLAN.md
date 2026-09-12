# HeaderGuard — Open Ideas

The original remediation plan (P0–P5, written against 0.1.2) is complete; see
`CHANGELOG.md` for what shipped in each release. What remains is optional and
unrequested. Neither is started.

## Structured CSP builder

Deferred from P3 (0.3.0). Today `content_security_policy:` is a raw string that
replaces the default wholesale, so adding one CDN to `script-src` means restating
every directive. A hash form — `{ "script-src" => ["'self'", "https://cdn.example"] }`
— merged over the default, directive by directive, would let users extend rather than
replace. Open questions: how a directive is removed (`nil`, as for headers?), whether
a String and a Hash can be mixed inside `path_overrides`, and whether merging means
"append sources" or "replace this directive". Wait for a concrete request before
designing it.

## Trusted publishing

Releases are pushed by hand with an API key plus an MFA code. RubyGems' trusted
publishing (OIDC from a GitHub Actions workflow) would remove the API key entirely:
a `release` workflow triggered by a `v*` tag builds the package and pushes it, with
`rubygems/configure-rubygems-credentials` and the gem's trusted-publisher entry
pinned to this repository and workflow. `data_redactor/.github/workflows/release-binaries.yml`
is a working example. Worth doing once the release flow has settled; the `/release`
skill's hand-off step would then become "push the tag".
