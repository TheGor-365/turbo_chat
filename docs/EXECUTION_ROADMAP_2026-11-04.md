> 2026-11-09 OWNER UI BACKLOG: Gate 2B.1 is owner-local accepted, with no provider. Home must become an actionable member hub; current PagesController homepage GET writes user offline status (P0). Account, Activity filters, icon/favicons and static 404/422/500 require phased Signal Deck polish; do not replace all controls in one commit. See [UI_UX_BACKLOG_2026-11-09_OWNER_REVIEW.md](UI_UX_BACKLOG_2026-11-09_OWNER_REVIEW.md). These are planned, not implemented; Gate 2B.2 composer draft-safe flow remains next.

# TURBO CHAT — EXECUTION ROADMAP / 2026-11-04

**Origin:** user's mandatory master specification `TURBO_CHAT_MASTER_PROMPT_CAREER_2026-11-03.md`. **Classification:** educational portfolio case; not a revenue-generating customer SaaS. Main branch remains unchanged; all work stays on PR #2 until explicit approval.

## Verified baseline

- Repo: https://github.com/TheGor-365/turbo_chat
- Source `main`: `b08ef33a9064454ef3770bd584c7735a151cd9be`.
- Branch: `feat/security-baseline-2026-11-03`; draft PR https://github.com/TheGor-365/turbo_chat/pull/2.
- First verified passing CI: https://github.com/TheGor-365/turbo_chat/actions/runs/41718077635 (14 Rails Minitest, 33 assertions, zero failures/errors/skips, frontend build + PG migrations).
- Previous implementation: security access guards, public-only global room activity, per-user message streams, removal of global arbitrary appearance payload relay, POST/DELETE room membership, model message/attachment validation, unique indexes, boot-time DB mutation removed, fixture/test repairs and security documentation.
- Drive: https://drive.google.com/drive/folders/1siG4TpA8aEJjnqih9OJD6FdR0TNQxyNG (five folders already exist). Baseline checkpoint: https://docs.google.com/document/d/12XnDWfiQhO8LECjT4anH7uTTJeii6o9sdx_f6BrJKoA/edit.
- No independent Railway Turbo Chat project, production live URL, qualified DEMO or screenshot pack yet.

## Work packages / completion gates

### P0 — Access control, information isolation and clean reliability
1. Request, model, channel and browser tests: guest / member / nonmember / third user for public and private room; forged user_id, arbitrary room_id, off-by-one IDs. All must deny improper reads/writes.
2. Active Storage: new controlled attachment endpoint must enforce owning room ACL. **Important:** original Rails built-in signed blob/representation URLs remain to be audited, revoked or disabled; introducing a private link alone does not complete private storage security. Replace all remaining URL generation and verify attempts using copied old links. Review avatars, image variants and long-lived signed links.
3. WebSocket/Turbo: test the signed stream token and session lifecycle, join, leave, forced removal, reconnect and stale clients. All future broadcasts must go only to current recipients; verify two browsers by network inspection.
4. Concurrency/data: index uniqueness for room names and memberships is committed with non-destructive duplicate preflight. Finish idempotent DM creation, transaction/retry on unique constraint, concurrency specs, deletion and orphan handling. No data-clearing migration.
5. Prevention: CSRF verification, session/cookie/CSP/HTTPS settings, rate limit signup/login/messages/search/upload, file validation by bytes where feasible, no risky file types, PII/log filters, private search scoping, query bounds and pagination.
6. Security scans: Brakeman, dependency audit, JS audit, secret history scanner with redacted output; evaluate legacy dependencies and image rights.

**Gate:** all P0/P1 access tests green; no unverified direct private attachment or stale stream access. Otherwise no public deploy.

### P1 — Supported stack / repeatable QA
1. Establish a reproducible clean boot and maintain minimum runnable CI while legacy Ruby 3.1.2/Rails 7.0.x remain.
2. Sequential supported Ruby/Rails upgrades with compatible Devise, Turbo, Pagy, Sprockets and JS build; no giant migration commit. Verify actual versions from official release documentation.
3. Define Redis vs Solid Cable in an ADR using Railway resource and reliability implications. Preserve PostgreSQL; avoid needless new frontend framework.
4. RSpec requests/models/channels + FactoryBot, SimpleCov, Playwright/Capybara system tests. Keep old Minitest until covered.
5. Run lint, security, assets, specs and Docker in GH Actions, with repeated seeded test runs.

**Gate:** versions locked, full suite repeatably green and clean Docker boot.

### P1 — Real product completion
1. Honest marketing page + DEMO explanation, working sign in / demo entry; login/signup/reset behavior must match configured SMTP.
2. Account display settings and avatar; safe session handling.
3. Public/group room creation/list/search/join/leave; DM uniqueness and access.
4. Message send/delivery, reload/reconnect, pagination; edit/delete own, length, safe rendering, errors.
5. Download/upload with private ownership and type/size validation; true image preview and document fallback.
6. Read receipts/unread counts and all/unread filter; real bounded presence heartbeat; in-app notifications. Choose reactions/typing/pin only when all mandatory behaviors verified.
7. Search restricted to the participant's accessible rooms, no data leaks; 403/404/422/429 and empty/loading states.

**Gate:** two independent browsers perform complete scenario without error or reload, including HTTP and WebSocket access denial.

### P1 — Design / UX
1. Check 5–7 relevant SaaS references; document two distinct design concepts and select one (original brand, no trade dress cloning).
2. Implement one restrained responsive enterprise messenger tri-pane desktop / stacked mobile, compact visual system, accessible icon actions, keyboard/focus and reduced-motion handling.
3. Verify 320/390/768/1024/1440 viewports, empty/error/accessibility states, real browser screenshots.
4. Produce original, properly licensed brand assets and fictional DEMO personas. No fake customer claims.

**Gate:** screenshot-based owner QA with all critical visual bugs resolved.

### P1 — DevOps / Railway release
1. Docker multi-stage, Compose, health endpoint, logs, database initialization, no secrets in image.
2. Decide persistent attachments store and WebSocket service; new dedicated Railway project, database, optional volume/bucket, review costs first. Never reuse Property Finder/Classifieds resources.
3. Migrate/seed idempotently; deploy staging, then production only after green release gates and budget approval.
4. Test public HTTPS + two-user WSS, restart and upload persistence, backup/restore, logs, rollback and egress.
5. Ensure SMTP/no-SMTP UX is honest; review leakage and demo account limits.

**Gate:** confirmed externally reachable URL and actual app workflows (not just 'SUCCESS' deployment).

### P2 — Portfolio and marketing proof
1. README EN/RU, architecture diagram, ADRs, threat model, QA evidence, operation docs and limits; license and asset rights checked.
2. Produce 20 genuine production screenshots, 10 desktop and 10 mobile, with timestamp, viewport, URL, SHA and redaction manifest; no generated UI substituted.
3. Produce editorial cover, OG, social card, slides/storyboard, optional 30–60 second real recorded demo; archive original and exports separately.
4. Save in existing five folders inside `07_TURBO_CHAT`: `01_FACTS_AND_COPY_RU_EN`, `02_SCREENSHOTS_VERIFIED`, `03_VIDEO_RAW_AND_AUDIO`, `04_MOTION_DESIGN_STORYBOARD`, `05_EXPORTS_READY`; perform readback.
5. Create standalone ZIP manifest + checksums and local copy; verify real repo/demo links; publish only after owner approval.

**Gate:** end-to-end proof pack is reproducible, attributable and safe for public portfolio.

### P2 — Handoff
Record final PR/main SHAs, Railway URL/project/service/storage, actual version matrix, CI links, runtime tests, screenshots, Drive URLs, limitations, remaining costs and issues. Never mark tests/production/screenshots 'DONE' without evidence. Main-branch merge and irreversible payments require separate authorization.

## Operational decision log

- No forced push, no merge, no data deletion, no changes to existing Railway projects.
- Security over visuals: do not expose a public app while private attachments and socket access remain unverified.
- Avoid marketing claims about SaaS customers, revenue or encrypted end-to-end chat.
- Release planning depends on verified tests, not calendar dates.
