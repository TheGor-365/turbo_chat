# Turbo Chat — storage durability and backup release gate

Updated: 2026-11-04. Status: **design + local regression only, NOT production-ready**.

## Local development
- `docker compose` binds the project checkout to `/app`. The ignored `storage/` directory on the host persists across ordinary `docker compose restart web` and `docker compose down`.
- PostgreSQL uses `turbo-chat-dev_postgres_data` named volume.
- New GitHub Actions Docker acceptance uploads a standalone Active Storage blob, restarts `web`, verifies the SHA-independent exact bytes from the same DB record, and purges the test object.
- This is **not** a backup: host disk loss still loses `storage/`, and `docker compose down -v` deletes the database volume.

## Private production disk (single-instance option only)
Production `config.active_storage.service` now selects `private_persistent_disk`.
It **refuses to boot** unless:
1. `TURBO_CHAT_STORAGE_ROOT` is an absolute path outside `Rails.root` and /tmp.
2. The directory exists and is writable by the Rails process.

Provision the volume on a **new dedicated service only**, for example mount
a Railway persistent volume at `/data`; create `/data/turbo_chat_private`
inside that mounted volume with appropriate permissions, then set
`TURBO_CHAT_STORAGE_ROOT=/data/turbo_chat_private`. Do **not** put this path
under the repository, the Docker image or an ephemeral build directory.
A valid directory is **not proof** that the mount is actually persistent.

This disk option is for **one application instance**. Multi-replica deployment
needs a truly shared private object store with a vetted adapter and access
controls; this is not configured yet. Default Active Storage public URLs stay
disabled, and downloads remain behind session/membership authorization.

## Backup contract before any public Railway deployment
- Require a verified database backup (`pg_dump` or provider snapshot) AND a
  backup of the private attachment volume with a matching retention window.
- Quiesce all uploads and mutations during a coordinated DB+file snapshot or
  accept and document consistency risks; backup files may contain sensitive
  user data and must be encrypted/restricted.
- Restore both components in a separate disposable environment. Verify
  actual login, room membership, private attachment bytes, restart, and WSS.
- Test deleted-file behavior, missing/partial volume, capacity and disk-full,
  rollback, backup retention and key access before releasing.
- Do not add backups containing user uploads to public Google Drive/GitHub.

## Still open
- Production mounting, restore drill, storage cost approval, and live HTTPS/WSS
  acceptance have **not** been performed.
- Full file decoding, malware scanning, content sanitization and access auditing
  are separate unfinished gates.
