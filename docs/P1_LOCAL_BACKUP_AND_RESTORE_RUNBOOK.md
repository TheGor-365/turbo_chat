# P1.1 — Local backup boundary and restore acceptance

Status: **owner-verified backup, checksums, isolated PostgreSQL/8 blobs restore and restored Rails HTTP/ACL acceptance** (2026-11-07). Production recovery NOT verified.
Branch: `feat/security-baseline-2026-11-03`, Draft PR #2 only.

## What we found
- Local development Compose uses a named PostgreSQL volume `postgres_data` containing `turbo_chat`.
- Local Active Storage uses `Rails.root/storage`. In the local Compose service, `.:/app` bind-mounts the working tree, so uploaded files live at `storage/` on the Linux Mint host. **A PostgreSQL backup alone cannot recover uploaded image/video/audio content**.
- Redis 7 in local Compose is configured with `--save "" --appendonly no`: it is ephemeral; it does not hold the canonical chat message history. Realtime state can reconnect; production presence/inbox transient behavior still needs explicit acceptance.
- The production configuration requires a writable persistent `TURBO_CHAT_STORAGE_ROOT`, but its durability and independent backups have **not** been verified. No Railway or production resources are changed.

## Explicit local backup (no auto-export or cloud upload)
Review local working tree and select a PRIVATE directory **outside the repo** first. Example:

```bash
git status --short
bash bin/backup_local.sh "$HOME/turbo_chat_private_backups"
```

The script creates a new timestamped, mode-0700 private directory containing:
- `database.dump`: PostgreSQL `pg_dump -Fc` (consistent database snapshot).
- `active_storage.tar.gz`: local `storage/` contents.
- `SHA256SUMS`: integrity checks for archive transfer.
- `README.txt`: explains that a full restore remains unverified.

No service stop, migration, schema dump/load, deletion of data volumes or network publication. This creates a **private** export of user and conversation data. Do NOT commit these artifacts to GitHub, upload to shared AI-indexed Drive folders, or send them in chat.

## Read-only validation (does not restore)

Run only after explicitly creating a local backup; pass the real generated directory path printed by the backup command:

```bash
bash bin/verify_local_backup.sh "/absolute/path/to/turbo-chat-YYYYMMDDTHHMMSSZ"
```

Checks SHA256 for both backup files, validates the gzip/tar archive listing and PostgreSQL custom-dump metadata (`pg_restore --list`). **No files are extracted, no database is created or modified.** It is safe to report the PASS/FAIL message without uploading the private archives. A passing integrity check does not prove an isolated restore.

**Consistency caveat:** The database and filesystem are captured sequentially, not atomically together; if another user uploads files concurrently, attachment references can mismatch. For production implement a consistent snapshot or brief planned write-quiescence; do not claim atomic recovery.

## Isolated restore drill (opt-in, never restores into current PostgreSQL)

The owner successfully executed this guarded drill against the 2026-11-06T23:07:36Z backup:

```bash
bash bin/restore_drill_isolated.sh "/absolute/path/to/turbo-chat-YYYYMMDDTHHMMSSZ" --isolated-restore-only
```

It first validates checksum/archive integrity, then starts a disposable `postgres:16-alpine` Docker container with `--network none`, **no published ports, host mounts, or existing named volumes**. The dump restores only inside that container. Files extract to a private temporary directory using Python's safe `tarfile` data filter (Python 3.12+); each Active Storage blob is validated against its backed-up checksum. It prints record counts, never message bodies. On completion/failure it stops the disposable container and deletes temporary files. Be sure the machine has adequate disk space and Docker access before opting in.

**Limits:** this is a DB plus file recovery *drill*, not a restored Rails application with two live browser sessions. It does not demonstrate application boot, authorization, actual video decoding, production RPO/RTO, or consistency across concurrent uploads. Production release remains blocked on those checks.

## P1.3 — Restored Rails application and private media HTTP acceptance

The owner successfully executed this explicit isolated Rails HTTP acceptance on their existing local backup:

```bash
bash bin/restore_app_acceptance.sh "/absolute/path/to/turbo-chat-YYYYMMDDTHHMMSSZ" --isolated-app-acceptance
```

Before running, review available Docker disk space and ensure Python 3.12+, Docker and the application development image dependencies are installed. Building the temporary Rails image may download public build dependencies if they are not cached. It does not upload the private backup. Do not run this from a Git checkout containing unreviewed Dockerfiles or other untrusted code.

The script:
1. Rechecks the private archive and extracts uploaded files safely into a new private temporary directory.
2. Creates an **internal Docker network** with a separate disposable PostgreSQL 16 and Redis; it publishes **no ports** and attaches **no existing Docker volumes**.
3. Restores PostgreSQL only inside the disposable container; builds a uniquely tagged throwaway Rails development image from the checked-out source. Secrets, storage and `db/schema.rb` are **not** mounted from the live app.
4. Launches Rails runner on the isolated network with a read-only application filesystem and read-only restored storage mount. Its guarded HTTP smoke probe confirms two real restored room members can view a populated private room and authorized media, a guest must sign in, and a synthetic **outsider created solely in the disposable database** is denied. Existing restored passwords are not changed or required.
5. Verifies a genuine private video poster and 206 byte ranges when the backup has eligible video; checks other available media types, without printing private contents, names or messages. Cleans up all temporary test containers, network, image tag and extracted data.

This is a **Rails HTTP-level integration drill**, not interactive Chrome UX testing, video playback in a browser or production recovery certification. P1.2 and P1.3 were both reported **PASS** by the owner on Linux Mint (2026-11-07). This does not validate production durability, another-host recovery, actual browser playback or RPO/RTO.

The isolated Rails test **does write a synthetic stranger user to the disposable restored database**, never to the real one. An interrupted process may leave disposable resources named `tc-restore-app-*`; inspect them explicitly before any manual cleanup, and never delete volumes used by the running `turbo-chat-dev` project.

## Restore acceptance — future isolated environment only
1. Create an **empty, disposable isolated database** with different Compose project name and separate volume; never restore into `turbo-chat-dev` or an existing `turbo_chat` database.
2. Restore `database.dump` with `pg_restore --no-owner --no-acl` to that empty DB; independently restore `storage/` into a sandbox working tree, **never into the existing source storage**.
3. Check SHA256 files, record counts, attachment count and verified attachment bytes; run a two-account private video/image fetch test in the isolated app. Compare original and restored metadata without displaying private content.
4. Record timestamp, environment, recovery duration and whether the restored app actually works. Only **then** elevate from “backup created” to “restore verified”.

This section intentionally does not present copy-pastable destructive restore commands until the isolated target and explicit consent are confirmed.

## Safety gates
- Do not run `docker compose down -v`, `db:reset`, `db:schema:load`, or `pg_restore --clean` on the live local project.
- Keep `db/schema.rb` local changes and the separate manual copy already made by the user.
- Production disaster recovery is NOT solved by these local scripts. See `docs/P1_PRODUCTION_BACKUP_RECOVERY_POLICY.md` for P1.4. Encrypted off-machine backup, retention, cross-machine restore, alerting and consistency still require approval and verification.
