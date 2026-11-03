# Security audit checkpoint — 2026-11-04

## Provenance and current state
- Repository: https://github.com/TheGor-365/turbo_chat
- Branch: `feat/security-baseline-2026-11-03` (draft PR #2; do not merge).
- New workflow: `.github/workflows/security-audit.yml`; run: https://github.com/TheGor-365/turbo_chat/actions/runs/41725593308
- Baseline Rails CI on same code commit: https://github.com/TheGor-365/turbo_chat/actions/runs/41725592703 — SUCCESS.
- Scanner outcome: both security jobs **FAIL**. This is an intentional and genuine release blocker; no advisories are suppressed or globally ignored.

## Findings — evidence from scanner output
| Scanner | Finding | Scope / interpretation |
| --- | --- | --- |
| Brakeman 7.1.1 | 2 high-confidence EOL dependency warnings | Ruby 3.1.2 unsupported since 2025-03-31; Rails 7.0.4.2 unsupported since 2025-04-01. No other Brakeman warnings in first run; this does NOT prove application security. |
| bundler-audit against ruby-advisory-db (last updated 2026-11-03) | 131 advisory entries across 24 affected gem names | actionmailer, actionpack, actiontext, actionview, activerecord, activestorage, activesupport, addressable, bcrypt, concurrent-ruby, crass, devise, loofah, mail, msgpack, net-imap, nokogiri, puma, rack, rails-html-sanitizer, rexml, rubyzip, selenium-webdriver, websocket-driver. Advisory count is not the number of distinct exploitable flaws in app. |
| Yarn Classic audit | 9 vulnerabilities among 50 packages: 1 low, 2 moderate, 6 high | includes legacy esbuild, braces, picomatch, immutable and source-map-js; confirm resolved package versions and reachability before changes. |

Do not treat the baseline Rails CI success as security approval.

## Mandatory follow-up work
1. Upgrade Ruby to a currently supported maintenance line in a separate, incremental commit; verify runner and development compatibility.
2. Upgrade Rails incrementally to a supported maintenance line; update associated Hotwire and authentication integrations with compatibility tests.
3. Regenerate `Gemfile.lock` and `yarn.lock` using actual dependency resolvers, not hand-edited text. Run full tests, then all three security scans again.
4. Assess transitive dependencies, advisories and production vs development exposure, document exceptions individually with sources; do not blanket-ignore.
5. Preserve security scanner jobs as blocking release gates.
6. Add authenticated browser two-user and storage/Redis integration tests; production deployment remains blocked.

## Important scope limits
- No dependencies have yet been upgraded or advisories fixed.
- Scanner reads public repository's dependency graph; it does not establish active exploitation.
- No Railway project or paid resources created; `main` remains unchanged.

## Ruby 3.4.12 migration started

Runtime pins updated to Ruby 3.4.12 in `.ruby-version` and `Gemfile`. This commit triggers a one-shot GitHub Actions dependency resolution; migration is not verified until a generated lockfile and full CI pass.

Dependency resolution trigger retried after fixing the workflow YAML condition. Only generated lockfile changes may be committed automatically to the existing feature branch.

CI found Minitest 6 API incompatible with Rails 7.0 test runner on Ruby 3.4.12. Gemfile now constrains Minitest 5. Resolve only this dependency, then run regression tests.

Ruby 3.4.12 and Minitest 5.27.0 confirmed in GitHub CI run 41727389358 (39 tests, 147 assertions, zero errors). Rails next step: 7.1.6 via Bundler, with rollback if CI fails.

Rails 7.1.6 requires Rack 3; Puma 5 refused Rails boot. Puma 6 is now the constrained version; Bundler lock regeneration underway.
