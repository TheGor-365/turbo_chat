# Turbo Chat / Relay Workspace

**Status:** Rails development release candidate in
[`feat/security-baseline-2026-11-03`](https://github.com/TheGor-365/turbo_chat/pull/2)
(Draft PR #2). **No public production demo, paid service, SLA or E2EE claim.**
Only synthetic or owner-authorized test data belongs in this environment.

## Product

**Turbo Chat** is a conventional messenger first: direct messaging, public
rooms, invite-only private groups, replies, reactions, file/photo/video/voice
attachments, notifications, presence, search, and realtime updates.
None of those requires AI.

**Relay Workspace** extends a permitted conversation into an *editable
deliverable*: automatic **local** source-aware Client Brief, optional
explicit gated model generation, private Save, immutable versions,
line-by-line comparison, and manual Markdown/text export.

For freelancers and small digital teams, the hypothesis is that fewer manual
steps between client discussions and reviewable documentation save time.
Demand, willingness to pay and retention have **not** been validated.

### Primary workflow

1. Sign in and discuss in a room with current membership.
2. Obtain the room participants' current opt-in before using private
   conversation content in contextual AI tools.
3. Open document review to generate an **offline extractive** Client Brief
   from permitted excerpts; unclear claims remain *to confirm*.
4. Explicitly Save v1, optionally edit to v2, inspect the version diff.
5. Explicitly **Export .md/.txt** of a selected authorized immutable version.
   This does **not** share to the room, publish, approve or invoke AI.

Team approval/share lifecycle is **not shipped**. Every downloaded document
must be reviewed by a person. No automatic Send.

## Stack and architecture

Ruby **3.4.12**, Rails **8.1.x** (lockfile specifies patched framework),
PostgreSQL, Redis/Action Cable, Hotwire (Turbo + Stimulus), ERB, Bootstrap 5,
Active Storage behind authorized Rails endpoints, Devise, Puma.
Production candidate Docker image and local Compose image are intentionally
**different**. See [architecture](docs/ARCHITECTURE.md),
[security boundaries](docs/SECURITY.md) and
[Railway deployment proposal](docs/DEPLOY_RAILWAY.md).

Testing includes Rails Minitest, controller and authorization regression tests,
Redis distributed transport, two-browser Chrome system acceptance, dependency
and static security scanning, development Docker smoke, and a separate
**non-deploying** production image build. Individual checks must be confirmed
for the **current SHA**; previous passes are not release acceptance.

## Local setup (existing data preserved)

Requires Docker Engine + Compose and Git on Linux/macOS.
This uses **local-only** containers and deliberately binds the HTTP port to
`127.0.0.1:3000`. It does not use Railway secrets.

```bash
git fetch origin
git switch feat/security-baseline-2026-11-03 || git switch --track origin/feat/security-baseline-2026-11-03
git pull --ff-only
docker compose up -d --build
docker compose logs --tail=50 web
```

Open `http://127.0.0.1:3000`. For the existing owner-local Jack/Eric room,
do not reset or reseed anything. A local `db/schema.rb` modification may
exist and must be examined, not overwritten. Do **not** use
`git reset --hard`, `git clean -fd`, `db:drop`, `db:reset`,
`db:schema:load`, `docker compose down -v`, or clear `storage/`.

Developer-only setup details:
[local development](docs/LOCAL_DEVELOPMENT_RU.md).

## Current release boundaries

- Public HTTPS/WSS deployment, production email/reset, billing, tenant isolation,
  support, retention policy, backup and restore, and security acceptance **open**.
- AI handling of room content requires explicit current consent/scope/budget;
  no claim of fact verification or legal approval from an AI output.
- Local document save/compare is owner-accepted; full browser export and
  deployment smoke remain gated by exact-SHA CI and owner review.
- Legacy inherited test skips are tracked; green checks alone do not prove
  full threat-model coverage, pen-test, SOC 2 or 24/7 availability.

[Release checklist](docs/RELEASE_CHECKLIST.md) ·
[Proposed Railway runbook](docs/DEPLOY_RAILWAY.md) ·
[RU/EN case study](docs/RELAY_CASE_STUDY_2026-11-12.md) ·
[Russian README](README.ru.md).

**Engineering portfolio / pilot inquiries:** see
[TheGor-365 on GitHub](https://github.com/TheGor-365).
No subscriptions or public trial are available until a separately approved R2.
