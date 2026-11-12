# Turbo Chat / Relay Workspace — release acceptance gates

Updated 2026-11-12; branch `feat/security-baseline-2026-11-03`, [Draft PR #2](https://github.com/TheGor-365/turbo_chat/pull/2).
A checked item is backed by the listed evidence only; **a passing CI suite is not a public deployment**.

## Gate A — source and reproducible CI (latest authenticated production smoke at SHA `86cb810`)

- [x] Rails request/model tests and two-browser Chrome system suite: [PASS](https://github.com/TheGor-365/turbo_chat/actions/runs/43238063456)
- [x] Automated security/dependency checks: [PASS](https://github.com/TheGor-365/turbo_chat/actions/runs/43238063275)
- [x] Docker Compose build/start smoke: [PASS](https://github.com/TheGor-365/turbo_chat/actions/runs/43238063334)
- [x] Production image build; clean PostgreSQL migrations; Redis; guest homepage and login; guest export HTTP 401; media persisted after web container replacement: [PASS in isolated CI](https://github.com/TheGor-365/turbo_chat/actions/runs/43243637938)
- [x] Production HTTP role matrix with three random-password synthetic users: Devise sign-in/CSRF, owner H5 export 200, participant non-owner H5 404, outsider H5 403, two authorized private attachment downloads 200, outsider attachment 404, live member consent revoke -> H5 403 and restore -> 200: [PASS in isolated CI](https://github.com/TheGor-365/turbo_chat/actions/runs/43243637938)
- [x] H5 saved draft v1/v2, live owner/source/consent ACL and explicit .md/.txt export: automated request tests in the Rails run; earlier local version/diff acceptance by owner
- [ ] Review any new P0 issues on the eventual **release** SHA and re-run all checks then; `main` is not merged

## Gate B — actual data safety (NOT accepted)

- [x] **Disposable synthetic CI recovery only:** paused source web, PostgreSQL 16 custom dump + private Active Storage snapshot, SHA-256 plus deliberate corruption rejection, independent restored DB/volume and production Rails ACL/media/H5 acceptance, cleanup: [PASS at `998d85d`](https://github.com/TheGor-365/turbo_chat/actions/runs/43288845039); [test scope](CI_BACKUP_RESTORE_2026-11-12.md)
- [ ] Concurrent-write consistent snapshot and repeatable recovery from *actual* Railway infrastructure, not proven by the CI test

- [ ] Preserve and reconcile owner's uncommitted `db/schema.rb`; no destructive schema or volume commands
- [ ] Actual operator-provisioned DB and media volumes verified across Railway restart/redeploy
- [ ] Transaction-consistent database + private media encrypted off-site backup, independently decrypted and restored to isolated environment, with checksums
- [ ] Rollback/recovery rehearsal and approved cost envelope

## Gate C — end-user acceptance (PARTIAL)

- [x] Owner accepted local H5 saved v1→v2 and diff; avoid repeating the same scenario
- [x] Owner screenshot confirms saved H5 v2, visible .md/.txt controls and .md system save dialog with correct v2 filename (2026-11-12)
- [ ] Confirm saved .md contents and completed .txt download on Linux Mint; screenshot proves dialog, not final filesystem bytes
- [ ] Realistic desktop/mobile user paths including auth, media, room messaging, notifications and AI-independent chat
- [ ] External two-user live websocket, reconnect and leave/removal behavior; private file access in two roles
- [ ] Photo/PDF/video seek/voice round-trip and mobile layouts; record environment-specific failures honestly

## Gate D — external infrastructure (NOT authorized / NOT deployed)

- [ ] Separate new Railway Turbo Chat project authorized by owner, with verified cost thresholds
- [ ] Public HTTPS/WSS and third-party browser checks on pinned release SHA
- [ ] Synthetic demo identities, safe signup/invites, no local Jack/Eric messages/credentials, disabled unapproved live AI
- [x] Controlled-access production R1 policy implemented in source: no self-signup or email reset until verified SMTP; existing accounts can log in ([policy](ACCOUNT_ACCESS_R1.md)); automated acceptance pending final CI
- [ ] Production SMTP/reset delivery **or** owner approval for an explicitly limited tester-only demonstration with no self-service recovery
- [ ] External monitoring, alerts, operational logs and backup restore

## Gate E — employer/pilot evidence (PARTIAL)

- [x] Honest guest positioning, RU/EN README, architecture and technical case study in repository
- [ ] Actual screenshots/video walkthrough with explicit local-versus-public evidence
- [ ] Public demo URL and pilot contact CTA verified after authorized launch
- [ ] Portfolio Drive asset upload/readback only when authorized; no fake customers or revenue claims
- [ ] Separate approval before `main` merge or any paid/published production rollout

**Current decision:** code candidate has a tested production-mode boot and three-user HTTP access matrix in disposable CI; **R1 PUBLIC DEMO BLOCKED** pending owner permission, real infrastructure/data recovery and external acceptance. **R2 PAID SERVICE NOT SHIPPED.**
