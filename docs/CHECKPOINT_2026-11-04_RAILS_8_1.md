# Rails 8.1.4 framework migration — verified checkpoint (2026-11-04)

## Verified changes

- Draft PR #2 / branch `feat/security-baseline-2026-11-03`; `main` unchanged. No Railway services modified or deployed.
- Ruby 3.4.12 retained.
- Rails **7.2.4 -> 8.0.5.1 -> 8.1.4**. Both intermediate steps regenerated `Gemfile.lock` through a genuine Bundler resolver on GitHub Actions (not manually edited).
- `User` ActiveRecord enum declarations changed from old keyword syntax to Rails 8 positional form (`enum :role`, `enum :status`), preserving role/status values and backing columns.
- One-shot lockfile generation workflows removed after successful completion.
- Rails 8.0.5.1 intermediate CI: https://github.com/TheGor-365/turbo_chat/actions/runs/41730614478 — SUCCESS, 39 tests / 151 assertions.
- **Final Rails 8.1.4 CI:** https://github.com/TheGor-365/turbo_chat/actions/runs/41731024374 — SUCCESS, 39 tests / 151 assertions / 0 failures / 0 errors / 0 skips, plus PostgreSQL and JS/CSS assets.
- **Rails 8.1.4 security audit:** https://github.com/TheGor-365/turbo_chat/actions/runs/41731024557 — fails overall as expected. Brakeman **0 security warnings**, but bundler-audit finds **6 advisory entries in 4 gems** (devise, puma, rubyzip, selenium-webdriver), and Yarn Classic finds **9 vulnerabilities in 50 packages** (1 low, 2 moderate, 6 high).

## Quality and release gates still open

1. Upgrade Devise, Puma and test-only webdriver/zip dependencies to supported safe versions; regenerate Gemfile.lock using Bundler and re-run complete Rails CI and audits.
2. Update JavaScript dependencies through Yarn, regenerating yarn.lock using the package manager and checking actual lockfile resolution. No ad hoc lock edits or ignore lists.
3. Check compatibility with new Rails defaults. `config.load_defaults 7.0` intentionally retained to avoid silent behavior changes; audit and test Rails 8 defaults individually before changing.
4. Real two-browser, two-account WebSocket/room membership and DM race QA, private attachment access and storage backend, Redis rate limit integration, CSP and upload content tests.
5. Dedicated Railway deployment (requires cost review, independent resources, storage and backup plan) not performed.
6. Do not merge draft PR or claim production readiness yet.

## Notes

Scanner advisory entries are not equivalent to independently exploitable vulnerabilities; review and remediate package and execution paths individually. The baseline test suite and Brakeman do not establish real production assurance.

## Ruby dependency remediation initiated

Devise constrained to 5.0.4+, Puma to 8.0.2+, obsolete webdrivers removed to unlock modern Selenium. A one-shot Bundler resolver is scheduled; do not claim vulnerability remediation until generated lockfile and independent scans confirm it.
