# Turbo Chat — isolated Railway demo deployment plan (NOT EXECUTED)

Prepared 2026-11-12 for draft PR #2. This is a **runbook proposal**,
not evidence of public availability, adequate backup, or a finished security audit.

## Release scope and hard gates

**R1:** synthetic-data, single-replica demo for employers and prospective
pilots. No client files, production AI billing, paid subscriptions, SLA, or
open access to Jack/Eric local accounts. H5 private Save/version compare/export
is in the branch; team approval is a separate unshipped workflow.
**R2:** commercial paid tenant/data/payment/privacy operations; not available.

Only after exact-SHA CI + security + Docker + production-image checks pass,
owner approves the budget and deployment, and rollback/data backup is ready:
create an **independent** Railway project `turbo-chat-relay-demo`. Do not reuse
or modify `property-finder`, `gor-web-resume`, `classifieds-rails-project-65`,
`github quality`, `reflect-ai-railway-staging`, or any existing database,
bucket, volume, domain or key.

Proposed isolated services:
1. `web` from this feature branch at a **pinned tested commit**, using
   repository-root `Dockerfile`, one replica, container port `PORT`.
2. New private PostgreSQL 16 service with its own persistent volume.
3. New private Redis service, for Action Cable and throttling (not the source of truth).
4. New private Rails Active Storage volume mounted at
   `/data/turbo-chat-private` on `web` only; single replica while using disk.
   A volume mount is not an encrypted off-site backup.
5. Railway-generated HTTPS domain only after owner approval and a demo
   data/abuse policy. Test WSS from two real independent browser sessions.

**Runtime environment variable names (never put values in this repo):**
- `RAILS_ENV=production`, `RAILS_SERVE_STATIC_FILES=1`,
  `RAILS_LOG_TO_STDOUT=1`, `PORT` supplied by Railway.
- `RAILS_MASTER_KEY` or a separately managed secure
  `SECRET_KEY_BASE` (preserve cryptographic identity across deploy/restart).
- `PGHOST`, `PGPORT`, `PGUSER`, `PGPASSWORD` for the *new*
  PostgreSQL service, matching `config/database.yml` production database
  `turbo_chat_pro`; validate DB creation and migrations before release.
- `REDIS_URL` for the *new* internal Redis service.
- `TURBO_CHAT_STORAGE_ROOT=/data/turbo-chat-private`;
  Railway supplies `RAILWAY_VOLUME_MOUNT_PATH` and `RAILWAY_VOLUME_NAME`.
  The production entrypoint refuses boot if they do not identify the same
  mounted directory. It grants the root directory to the non-root Rails user
  and then drops privileges. **A production-mode Docker boot and private media persistence test passed in disposable CI; actual Railway volume boot and backups remain unverified.**
- `XAI_CONTEXT_REPLIES_ENABLED` and any other provider-enable flags: **off**.
  No live `XAI_API_KEY` in public demo unless an explicit cost+privacy
  approval and server-side usage cap have been verified.

Never use development Compose credentials or the local `.env.local`.
Never put secrets in GitHub issues, docs, logs, Drive portfolio, or chat.
`.dockerignore` excludes local environment, runtime files and master keys.

## Mandatory pre-deploy checks (manual/approved only)

- Review `db/schema.rb` diff and `db:migrate:status`; maintain existing
  owner-local modified `db/schema.rb`. No `db:reset`, `db:drop`,
  `db:schema:load`, `docker compose down -v`, or resetting storage.
- Production image: check asset build, app boot with mounted volume,
  application-generated URL/cookie settings, Rails static file delivery,
  TLS forwarded protocol, WSS origin and reconnection behavior.
- Migrate the **new empty demo DB only** after a verified snapshot/revert plan.
  No local Jack/Eric credentials/messages in public seeds. Create constrained
  synthetic DEMO users/rooms with limited signup/traffic; no shared privileged
  password in source.
- Operator-only protected backups: consistent PostgreSQL and volume data,
  encrypted/off-site storage and isolated restore of both with media byte
  verification. See `P1_PRODUCTION_BACKUP_RECOVERY_POLICY.md`.
- Verify denial of direct IDOR access as guest, outsider, removed member and
  revoked-consent user for messages, media and H5 exports; verify no paid AI
  calls and no unintended Chat Send.
- Rollback to previous working **pinned image**; restore only into a separate
  tested environment. Database migrations must be assessed for backward
  compatibility before applying to a running instance.
- External browser smoke: HTTPS signup/login, two sessions DM + group
  realtime without F5, PDF/photo/video download ACL, saved H5 v1/v2 export,
  restart + file persistence, then verify backup/restore in isolation.

**Do not switch a real service to this Dockerfile automatically.** The CI job builds an unpushed image and exercises it against new disposable PostgreSQL/Redis and private bind storage. It performs no external deployment and grants no authority to deploy or merge `main`.

## Cost envelope, subject to Railway dashboard confirmation

Official Railway pricing as checked 2026-11-12:
https://docs.railway.com/pricing/plans
Hobby minimum is $5/month, including $5 of usage across the workspace,
**not $5 extra credit for this project**. Resource rates: RAM $10/GB-month,
CPU $20/vCPU-month, persistent volume $0.15/GB-month,
service egress $0.05/GB. New web, PostgreSQL, Redis, and 2 volumes add
metered consumption to the existing projects. A planning placeholder is
**$10–30/month additional** for a small always-on synthetic demo, *not*
a quote, fixed cost or upper limit. Verify workload forecasts, billing
alerts, daily spending and invoice on the actual workspace before consent.
Never start paid storage or production AI simply to measure the bill.

Railway volume constraints:
https://docs.railway.com/volumes
https://docs.railway.com/volumes/reference
Volume mount exists only at runtime (not build or preDeploy); attached
volumes limit the web service to one replica and may cause a short deployment
restart. The proposed root-owned volume handoff runs only during the entrypoint.
Production restart durability and real isolated restore remain unverified.

## Present state

- **Verified in isolated GitHub Actions at SHA `9f27d83`**: Docker build, production Rails boot after migrations of a fresh temporary PostgreSQL 16, Redis connectivity, fail-closed boot without volume, guest homepage and login, guest H5 export denied with HTTP 401, and Active Storage private byte persistence after deleting and recreating the web container. [CI evidence](https://github.com/TheGor-365/turbo_chat/actions/runs/43238063184).
- **Not yet verified**: actual Railway volume/production runtime, externally accessible HTTPS/WSS, two-user external realtime and private media ACL, production backup plus isolated restore, email deliverability, Railway resources or domain, owner billing approval, and commercial operations.
- **Do not call this production-ready or publicly available.**
