# CSP + Redis rate limiting and PostgreSQL race hardening — 2026-11-04

## Verified scope
Branch: `feat/security-baseline-2026-11-03`; Draft PR #2. No merge to `main`, no Railway deployment.

### CI evidence
- Rails CI https://github.com/TheGor-365/turbo_chat/actions/runs/41742448458 — **SUCCESS**:
  - 51 Rails tests, 201 assertions, 0 failures/errors, 2 intentional skips (Redis-only test cases in ordinary suite).
  - Separate real Redis integration step: 2 tests, 6 assertions, zero failures/errors/skips.
  - Headless two-session Chrome system acceptance: 3 tests, 37 assertions, zero failures/errors/skips.
  - Frontend build and PostgreSQL migration completed.
- Security audit https://github.com/TheGor-365/turbo_chat/actions/runs/41742448711 — **SUCCESS**: Brakeman, bundler-audit, Yarn audit.

### Implemented
1. Enforced CSP in `config/initializers/content_security_policy.rb`: default-src self; base-uri self; object-src none; frame-ancestors none; form-action self; script-src self (no inline scripts); img-src self/data/blob; font-src self/data; connect-src self/ws:/wss:. Existing Bootstrap + dynamic inline styles require temporary `style-src 'self' 'unsafe-inline'`; this exception is explicit and MUST be tightened later.
2. Added CSP HTTP integration test asserting policy is enforced rather than report-only.
3. CI Redis 7 service on port 6379 and a dedicated Redis test step for two independent cache connections plus concurrent atomic increments. `RequestThrottle.exceeded?` now permits explicit cache injection for isolated tests.
4. Fixed real Redis production bug: RedisCacheStore `increment` operates on raw numeric values; previous serialized zero caused `nil` and fail-closed errors. The initial conditional write now uses `raw: true` and a TTL, so atomic increment is valid in Redis and MemoryStore.
5. Concurrency stress exposed sporadic canonical DM create race (`RecordInvalid name taken`). Added transaction-scoped PostgreSQL advisory lock per canonical DM name, preserving unique index and existing row validation. Query is parameterized with 64-bit integer bind, not interpolated SQL; Brakeman zero warnings.
6. All one-time deployment and production config remain unchanged beyond this feature branch.

### Residual P0 gates
1. **File content validation not yet implemented.** Current Message/User model upload checks rely on declared content type, file count and byte size. Validate actual bytes/magic signature before accepting inline images and attachments; reject spoofed data; ensure UX for rejected uploads.
2. Redis check validates actual shared **counter** behavior, not Redis-backed ActionCable pub/sub across separate app processes nor Railway-managed Redis availability/failover.
3. CSP style-src unsafe-inline exception remains; inline CSS in layout and Bootstrap need refactor; connect-src currently allows scheme-wide ws/wss and should be restricted to configured hosts in deployment.
4. Production Active Storage remains local Disk, no durable external object store or backup/ACL integration. Do not deploy Railway without choosing persistent storage.
5. Rails 8.1 default settings, actual production cookie/CSRF and mobile/responsive acceptance remain unverified.

Do not call this production-ready.
