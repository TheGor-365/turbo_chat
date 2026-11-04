# Turbo Chat checkpoint — local preview and P0/P1 follow-through (2026-11-04)

## User-local evidence
- Linux Mint checkout on `feat/security-baseline-2026-11-03`.
- `docker compose up -d --build` built the Ruby 3.4.12 dev image.
- `docker compose ps`: PostgreSQL and Redis HEALTHY; Rails web running and bound to 127.0.0.1:3000.
- **No browser screenshot or actual user-local HTTP response provided yet.**
- Native `bin/rails s` under host Ruby 3.4.7 is expected to fail; Docker has pinned Ruby 3.4.12.

## Shipped to working branch
1. Private production disk root now fails closed without a writable, absolute persistent path outside Rails.root/tmp; backup/restore and a real attached volume are still unverified. `docs/STORAGE_DURABILITY_AND_BACKUP.md`.
2. Docker smoke confirms an Active Storage blob can be uploaded, the web container restarted, and identical bytes read back. CI PASS: https://github.com/TheGor-365/turbo_chat/actions/runs/41815830242.
3. Whole-file size-bounded structure screening: full UTF-8/NUL inspection, PNG chunks/CRC/dimensions, WebP RIFF length, JPEG EOI and PDF EOF envelope. Not a decoder, AV scan or guarantee of safe content. Rails CI PASS: https://github.com/TheGor-365/turbo_chat/actions/runs/41816442432.
4. ActionCable Redis transport integration across two processes; dedicated CI step PASS after test adapter isolation fix: https://github.com/TheGor-365/turbo_chat/actions/runs/41817205189. This is not full cross-instance Chrome/WebSocket QA.
5. Fixed historical message pagination (`@pager` -> `@pagy`), with two request tests for authorized and forbidden history access. The final pagination revision requires a new HEAD CI confirmation.

## Latest independently confirmed workflows
- Rails CI (Redis cross-process): PASS https://github.com/TheGor-365/turbo_chat/actions/runs/41817205189
- Security audit: PASS https://github.com/TheGor-365/turbo_chat/actions/runs/41817205413
- Docker build, HTTP smoke, persistence: PASS https://github.com/TheGor-365/turbo_chat/actions/runs/41817205210

## Release blockers
- Validate production volume mount and real restore with DB/file consistency.
- Verify distributed browser WebSockets on two Rails instances plus revoke/reconnect.
- Full media decoding/sandboxing and threat assessment beyond structural checks.
- Docker production build, RSpec/lint, complete SaaS UX, staging/production.
- No merge to main, no Railway changes, no paid resources or public demo.

## Immediate next user action
Open http://127.0.0.1:3000 and share screenshot or the result of
`curl -I http://127.0.0.1:3000`. No need to change system Ruby.
