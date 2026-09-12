---
name: release
description: Release a new version of the header_guard gem. Dates the CHANGELOG, runs the suite on Rack 2 and 3, merges to main, tags, pushes and builds the package. The user runs `gem push` themselves.
---

# Release header_guard $ARGUMENTS

Release the version given in `$ARGUMENTS` (e.g. `/release 0.4.0`). If no version is
given, read it from `lib/header_guard/version.rb` and confirm it with the user before
doing anything else.

## Ground rules

- **Never run `gem push`.** It needs the user's RubyGems credentials and a one-time MFA
  code (the gem sets `rubygems_mfa_required`). The last step of this skill is handing the
  user the exact command.
- **Do not merge, tag or push without the user's explicit go-ahead** for this release.
  "Continue" or "ok" on an unrelated point is not a go-ahead. Ask once, plainly.
- **Build the package only at the end, only once.** A `.gem` built mid-work sits in the
  repo directory looking like a release build, and the user may push it. (This happened
  in 0.3.1: the published package had stale docs.) If a build is needed for inspection
  earlier, write it to the scratchpad with `gem build header_guard.gemspec -o <scratch>/x.gem`.
- Semver: **patch** for bug fixes and packaging changes; **minor** when defaults, injected
  headers or response scope change, or when previously-accepted configuration now raises.

## Preconditions (check, don't assume)

1. On a feature branch, working tree clean, all work for the release committed.
2. `lib/header_guard/version.rb` already holds the target version.
3. `CHANGELOG.md` has the release notes under `## [Unreleased]` (usually beginning
   "Targeting X.Y.Z.").
4. `PLAN.md` reflects what this release finishes.

## Steps

1. **Test on both Rack majors.** Stop on any failure.
   ```bash
   bundle exec rspec
   BUNDLE_GEMFILE=gemfiles/rack_2.gemfile bundle install --quiet && BUNDLE_GEMFILE=gemfiles/rack_2.gemfile bundle exec rspec
   BUNDLE_GEMFILE=gemfiles/rack_3.gemfile bundle install --quiet && BUNDLE_GEMFILE=gemfiles/rack_3.gemfile bundle exec rspec
   ```
2. **Date the CHANGELOG.** Replace the "Targeting X.Y.Z." line under `## [Unreleased]`
   with a pointer to remaining work, insert `## [X.Y.Z] - YYYY-MM-DD` (today's date)
   above the notes, and update the compare links at the bottom:
   `[Unreleased]: .../compare/vX.Y.Z...HEAD` and
   `[X.Y.Z]: .../compare/vPREV...vX.Y.Z`.
3. **Commit** as `Release X.Y.Z` with the `Co-Authored-By` trailer.
4. **Merge and tag** (after the go-ahead):
   ```bash
   git checkout main && git merge --ff-only <branch>
   git tag -a vX.Y.Z -m "vX.Y.Z - <one-line summary>"
   git push origin main --follow-tags
   git branch -d <branch>
   ```
5. **Build once, verify.**
   ```bash
   gem build header_guard.gemspec
   tar -xOf header_guard-X.Y.Z.gem data.tar.gz | tar -tzf - | sort
   ```
   Require: zero `WARNING` lines from the build, version matches, and the package is
   exactly these nine files — nothing more, nothing less:
   `CHANGELOG.md Gemfile Gemfile.lock LICENSE.txt README.md header_guard.gemspec
   lib/header_guard.rb lib/header_guard/middleware.rb lib/header_guard/version.rb`.
   Anything else (a `.gem`, `PLAN.md`, `spec/`, `gemfiles/`, `.claude/`) means the
   gemspec reject list has a hole; fix that before handing off.
6. **Hand off.** Report: `main` commit, tag, package file list, both suites green. Then:
   > Yours to run: `gem push header_guard-X.Y.Z.gem` (it will ask for your MFA code).
7. **After the user confirms the push**, verify what actually went out:
   ```bash
   cd <scratch> && gem fetch header_guard -v X.Y.Z
   # extract both and diff -r against the local build
   ```
   Report any difference. A published version cannot be replaced; a docs-only
   difference is not worth a new release, a code difference is.
