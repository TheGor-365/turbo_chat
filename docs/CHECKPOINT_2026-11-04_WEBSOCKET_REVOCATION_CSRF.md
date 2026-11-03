# WebSocket membership revocation + CSRF acceptance — verified checkpoint (2026-11-04)

## Verified code and tests
- Draft PR #2 only, branch `feat/security-baseline-2026-11-03`; `main` and Railway untouched.
- Rails CI **SUCCESS**: https://github.com/TheGor-365/turbo_chat/actions/runs/41740346298
  - 48 Rails unit/integration tests, 184 assertions, 0 failures/errors/skips.
  - 3 real Chrome/Capybara system tests, 41 assertions, 0 failures/errors/skips.
  - Frontend build and PostgreSQL preparation passed.
- Security audit **SUCCESS**: https://github.com/TheGor-365/turbo_chat/actions/runs/41740346350 (Brakeman, bundler-audit, Yarn audit).

## New security behavior exercised in real browsers
1. Alice and Bob sign in with separate browsers and receive room messages via actual ActionCable async broadcast.
2. A separate HTTP client authenticates Alice and removes her room membership while her Chrome room tab remains open; Bob sends a new message. Alice does not receive the post-revocation broadcast. Direct navigation to the now-forbidden room does not expose a composer.
3. After legitimate rejoin, Alice can reopen the room, see existing authorized history, and receive new live messages.
4. CSRF protection is **enabled for system test runs** via `SYSTEM_TEST_REALTIME=1` and remains disabled only for ordinary isolated unit/integration Rails tests. Both real browser forms and separate authenticated HTTP test client carry actual CSRF tokens.
5. Negative CSRF test confirms a logged-in state-changing room-create request without token is rejected with HTTP 403/422 and no room is created.
6. Production `config/cable.yml` requires `REDIS_URL`, without silently falling back to localhost; configuration ERB only requires it in production to permit test/dev boot.

## Evidence limitations and next gates
- This proves revocation in a single-process headless Chrome/system-test ActionCable **async** environment; it is NOT proof of Redis pub/sub across multiple instances or Railway behavior.
- Session logout, expired-cookie WebSocket reconnect and malicious websocket origin testing are not all covered.
- Need enforceable, browser-tested Content Security Policy; inspect legacy inline styles in application layout and any external assets.
- Need real Redis cache/pub-sub integration and private object storage backend including invalid/spoofed image bytes, uploads and backpressure.
- Need Rails 8.1 defaults review, separate Railway staging and responsive/mobile acceptance.
- Do NOT merge into main or deploy production until outstanding release gates are resolved.
