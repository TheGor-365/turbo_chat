# Delivery roadmap (release gates)

Audited baseline: `b08ef33`, 2026-11-03. Scope: one credible team-chat SaaS DEMO; demo accounts fictional; no payment promises.

| Gate | Priority | Deliverable | Acceptance evidence |
|---|---|---|---|
| 0 | P0 | source baseline, threat model, isolated branch | files committed, source SHA |
| 1 | P0 | auth/ACL, room/membership HTTP, global broadcast isolation, DM naming, negative request tests | CI runs and proofs for guest/outsider/admin |
| 2 | P0 | authorized private attachments, storage limits/types; database uniqueness & migration preflight; rate limiting | tests for third-party access, duplicate/concurrent inserts |
| 3 | P1 | baseline CI and reproducible container, pinned supported dependencies | clean bundle+JS+Postgres+Redis, all tests green |
| 4 | P1 | incremental Rails/Ruby upgrade (Rails 7.0→7.1→7.2→8.0→8.1), library compatibility and frontend | green CI, verified version matrix, asset compile after each gate |
| 5 | P1 | message edit/delete, unread counters, profile, durable presence, search, notifications | two independent browser sessions, all negative specs |
| 6 | P1 | UX design system, marketing, mobile and accessibility | genuine desktop/mobile screenshots & keyboard review |
| 7 | P1 | Docker/Compose, security scans, tests, logs, backups | full CI and clean smoke, threat model evidence |
| 8 | P1 | *isolated* Railway project, Postgres, Redis, persistent private files | HTTPS/WSS two-client smoke, persistence and restore, cost approval |
| 9 | P2 | RU/EN case, genuine screenshots, verified asset rights, Drive kit | screenshot manifest, readback, ZIP checksums |
| 10 | P1 | release handoff, review | final release checklist met; merge to main only with user approval |

**Excluded:** calls, paid billing, cross-tenant AI assistant, speculative metrics, pretend E2EE. Optional P2: emoji reactions and typing after P0/P1 confidence.

### Design alternatives (decision pending browser review)
A) **Graphite / Iris:** calm neutral surfaces, purple accent, dense tri-pane desktop, stacked mobile; recommended for low complexity/accessibility.
B) **Polar / Cyan:** high-contrast dark-led UI with cyan semantic accents; more visual branding but harder contrast, more layout tuning.
Choose a single coherent system after actual rendering; no unlicensed screenshots/logos.

### Verification notation
Use VERIFIED (with link/log), SOURCE-INSPECTED (code only), NOT VERIFIED, BLOCKED. Do not mark green until actual checks.
