# Turbo Chat — abuse prevention and session security checkpoint (2026-11-04)

## Verified code and quality

- Branch `feat/security-baseline-2026-11-03` remains draft PR #2; `main` unchanged; Railway not touched.
- Rails CI after main throttle + model changes: https://github.com/TheGor-365/turbo_chat/actions/runs/41724895091 — SUCCESS: 39 tests, 147 assertions, 0 failures/errors/skips, PostgreSQL initialization and frontend build.
- The production runtime has NOT been booted; the browser acceptance gate remains open.

## Implemented

1. `RequestThrottle`: SHA-256 identity token, independent scope and fixed windows, conditional atomic counter initialization, count increment; fails closed if counter unavailable. 
2. `ThrottledRequests` returns HTTP 429, `Retry-After` and `Cache-Control: no-store`.
3. Scope limits: authenticated message creation 30/minute per user+remote IP; room create/join/leave 15/minute; room search 30/minute; login attempts 10/10 minutes per IP; signup/account update 5/10 minutes per IP. No direct use of client-supplied forwarding headers in the throttle.
4. RedisCacheStore in production with mandatory `REDIS_URL`, shared across workers; MemoryStore in local/test. Production SSL forced and security headers enabled.
5. Private content and account fields are filtered from Rails request logs (body, attachments, avatar, email).
6. Avatar upload model validation for JPEG/PNG/WebP and 5 MB limit; delivery controller already uses own checks.
7. Added unit tests on scopes, identity isolation, time window, invalid limits, actual 429 message burst, avatar MIME/size.

## Remaining security risks and gates

- Current limiter is fixed-window, allowing bursts at window boundaries. Distributed Redis tests, retry semantics and reverse-proxy trust settings need real Railway verification.
- Production `REDIS_URL` must be configured in **dedicated** Railway project before app boot.
- These are metadata MIME checks, not confirmed inspection of bytes; spoofed content-type, ZIP bombs and image decompression limits remain to be audited. Multipart upload body-size guard at reverse proxy must also be set.
- CSRF/cookie policy and enforceable CSP remain to be configured/tested against actual Turbo/Bootstrap scripts.
- Brakeman/dependency/JS scanner and supported Ruby/Rails upgrade not yet complete.
- UI/browser two-account scenarios and real concurrent DM tests outstanding.
- This is not production-ready and must not be merged/deployed publicly.
