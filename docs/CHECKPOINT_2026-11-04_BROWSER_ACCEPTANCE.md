# Realtime browser and access acceptance — verified checkpoint (2026-11-04)

## Evidence and scope

- Repository TheGor-365/turbo_chat. Work performed only in `feat/security-baseline-2026-11-03` (Draft PR #2); `main` and all Railway services unchanged.
- Rails baseline + independent PostgreSQL concurrency tests + authorized file/room lifecycle: https://github.com/TheGor-365/turbo_chat/actions/runs/41736818933 — **SUCCESS**.
- **48 Rails tests, 184 assertions, 0 failures / errors / skips**.
- **1 headless Chrome realtime system test, 13 assertions, 0 failures / errors / skips**. It uses two separate Capybara browser sessions, two real Devise logins, live ActionCable async adapter and actual Turbo stream delivery from Alice to Bob in a shared room.
- Independent security audit: https://github.com/TheGor-365/turbo_chat/actions/runs/41736818964 — **SUCCESS** for Brakeman, bundler-audit and Yarn Classic audit.

## Changes and findings

1. Added channel tests for stream replay between rooms, signed stream name identity, private room participants vs. joinables.
2. Added integration tests for leave/rejoin HTTP ACL, old attachment URL revocation after leave, separate accounts and private documents.
3. Added `ConcurrentDirectRoomTest` with four independent PostgreSQL connections; confirms a single canonical DM with exactly two participants.
4. Added actual Chrome `test/system/chat_realtime_system_test.rb`; CI now invokes `bin/rails test:system` with live ActionCable async adapter in test mode only. All ordinary Rails unit/integration tests retain ActionCable test adapter.
5. Devise 5 legacy custom responder was incompatible with real browser signin. Switched Devise to native Turbo/HTML responder and modern error/redirect statuses; login form uses full HTML navigation. Added credential-based HTTP login regression test.
6. Replaced home page direct Active Storage variant URL with authenticated `user_avatar_path`.
7. Browser revealed large, unconstrained navbar avatar expanding header to ~2548px and pushing chat below the viewport. Constrained navbar avatar to 40x40 and home image to 150x150; revised chat CSS to keep composer visible in a scrolling flex layout.
8. Removed temporary diagnostic logging after identifying the layout error.

## Release blockers / not yet verified

- The headless browser test confirms **message receipt for two concurrent authorized sessions**, but does not yet simulate leave and reconnect in live browsers, cross-account attack in a real socket, network disruption or browser mobile layouts.
- CSRF enforcement in the test environment is disabled by existing configuration; real production CSRF/session behavior needs testing.
- Redis distributed rate limiting, production file storage provider ACL and image-byte validation need integration tests.
- New Rails 8.1 defaults still need review. `config.load_defaults 7.0` retained intentionally.
- CSP, accessibility/responsive layout audits, production browser QA, Railway staging resources, backups, costs and deployment not performed.
- The original `TurboDeviseController` class is now unused; remove it separately only after verifying references.

Current release state: security scanners and existing tests green, browser realtime delivery confirmed; **not production ready** until remaining P0 gates complete.
