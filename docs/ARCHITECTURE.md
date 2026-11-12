# Turbo Chat / Relay Workspace — current architecture (2026-11-12)

Status: source-level description of draft PR #2; not an external audit.

```text
Browser: ERB / Turbo / Stimulus / Bootstrap
  | HTTPS + session cookies                 | WSS
  v                                         v
Rails 8 / Puma (Devise auth + room ACL) ---> Action Cable / Redis transport
  |                  |                      (ephemeral presence / rate limits)
  |                  v
  |           PostgreSQL (users, rooms, messages, consents,
  |            AiDeliverable, immutable AiDeliverableRevision)
  v
Authenticated private attachment controller ---> Active Storage private disk
  |
  +-- AI Workspace: bounded authorized excerpts, DLP/consent/scope checks
  |      +-- offline extractive Client Brief (no provider cost)
  |      +-- optional user-triggered xAI request
  |          (feature flag, unanimous consent, budget gate; dev only)
  |
  +-- H4 structured preview: inferred / unknown / needs_confirmation
         |
         +-- explicit H5 Save -> new record v1
         +-- edit -> immutable v2 -> exact line comparison
         +-- explicit GET export.md / export.txt (owner + live ACL)
```

## Data and trust boundaries

- **PostgreSQL:** persistent room memberships, chat messages, individual
  read state, AI consent and saved documents/revisions.
- **Redis:** WebSocket transport and rate-limits, not a source of persistent
  chats or documents. Multi-process and reconnect behaviors have tests.
- **Active Storage:** private controller routes; raw public blob routes are
  disabled. Production disk requires a writable independent persistent mount
  and verified backup/restore. One web replica only with that disk option.
- **Session and authorization:** Devise and room membership checks on each
  protected request. H5 document reads/exports additionally require owner,
  current room consent and live source-author membership across saved versions.
  Revocation denies read and download. Markers `[M123]` are references,
  not proof that an item is agreed or true.
- **AI:** normal chat does not call a model. H4 default drafts are local.
  Optional xAI context calls are separate explicit and gated actions; never
  export whole private room history by default. Keep model API keys out of
  GitHub and demo environments.
- **Output:** H5 Export downloads a snapshot of the selected immutable
  revision only. It never posts a message, approves terms or invokes billing.
  No cross-person approval lifecycle exists in this release.

## Local vs release-candidate topology

Local: `compose.yaml` builds `Dockerfile.dev`, uses private Postgres/Redis
containers, no host-exposed DB/Redis ports, local host-backed storage, and
localhost-only web access. Not production security evidence.

Production candidate: root `Dockerfile` precompiles assets; runtime entrypoint
demands a Railway-attached volume and starts Puma as a non-root user.
`docs/DEPLOY_RAILWAY.md` describes an isolated future Railway project with
dedicated PostgreSQL, Redis and media storage. **No public deployment
or recoverability proven.**

## Key incomplete contracts

Cross-member proposal/approval/consent versioning; email delivery,
multi-tenant billing, backup/offsite decryption and isolated restore,
production load/security acceptance, deployment uptime, retention,
support/abuse handling and commercial onboarding.
