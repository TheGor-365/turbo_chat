# Operator-controlled offline recovery — preparation only

Updated: 2026-11-12. **NOT executed or production-accepted.**
Companion to [P1 backup policy](P1_PRODUCTION_BACKUP_RECOVERY_POLICY.md)
and [synthetic CI recovery evidence](CI_BACKUP_RESTORE_2026-11-12.md).

## Purpose and non-negotiable boundaries

This runbook prepares the owner to rehearse **nonproduction** recovery with a recovery key held on a separate trusted machine. The private identity **must not be sent to ChatGPT, GitHub, Railway, shared Drive, screenshots, or an AI-indexed folder**, nor stored alongside the encrypted archives. Use a second independently protected offline recovery copy. No keys, external accounts, storage buckets or real-data backup are created by these instructions.

**Do not run this against the current local Turbo Chat database without an explicit data-protection decision.** Do not reset, migrate, clean, detach or delete developer PostgreSQL, local `db/schema.rb`, any Docker volumes or previous backups. This is an acceptance plan, not a tested service.

## Prerequisites before beginning

- A **synthetic or explicitly approved sanitized backup** created using existing repository backup tooling; known PostgreSQL database name and compatible archive layout. The local `restore_drill_isolated.sh` currently expects a *development* `turbo_chat` database and media layout from `bin/backup_local.sh`, not CI's `turbo_chat_pro` recovery format.
- A different, trusted recovery computer with `age`, `sha256sum`, PostgreSQL 16 tools and Docker installed, with no private backup folders syncing automatically to cloud.
- Sufficient free local disk; a protected location for decrypted artifacts (`umask 077`), outside Git, shared folders and public serving paths.
- Explicit owner approval of the nonproduction dataset and any removable-media transfer method.

## Owner-only sequence (not performed by the assistant)

1. **On a trusted offline recovery device**, generate an `age` X25519 identity with `age-keygen`, restrict the private identity to the operator and create an independently stored recovery copy. Confirm the second copy works without revealing its contents. The public `age1...` recipient can be supplied to the encryptor; only that recipient belongs on the source machine. Keep secret-key material out of terminals/screenshots shared in chat.
2. On the *source machine only*, with an existing **verified synthetic/sanitized snapshot**, encrypt it using `bash bin/encrypt_local_backup.sh /absolute/source-backup-dir /absolute/encrypted-output-parent age1PUBLIC_RECIPIENT --encrypt-only`. Do not select real user backup content for this first drill.
3. Validate the ciphertext in the output folder using `bash bin/verify_encrypted_backup.sh /absolute/encrypted-backup-dir`. This validates **transfer integrity only**, not recovery. The encryptor **retains** the plaintext source, by design.
4. Transfer **only** `database.dump.age`, `active_storage.tar.gz.age`, `SHA256SUMS.age` and `CIPHERTEXT_SHA256SUMS` via an owner-approved encrypted/offline transport to the second machine. Never bundle a private identity with ciphertext.
5. On the second machine, create a new, restricted, **non-synced** directory outside the repository; verify the ciphertext hashes again. Use local `age -d -i /private/offline/recovery-identity.txt -o /safe/private/restore/database.dump /safe/encrypted/database.dump.age` and likewise decrypt the other two `.age` files. Do not print or share decrypted contents.
6. Validate `SHA256SUMS` inside the decrypted directory, then `bash bin/verify_local_backup.sh /absolute/decrypted-backup-dir`. If anything fails, **stop**: do not restore an incomplete pair.
7. Restore only into a **new, isolated** PostgreSQL and a separate private file directory. For compatible **development-format** backups, the existing `bin/restore_drill_isolated.sh` performs a read-only source / disposable DB check. Do not aim any restore commands at a running source database or substitute the CI `turbo_chat_pro` archive as if it were the dev layout.
8. Record proof without private content: hash-check result, count of recovered DB objects/blobs, ACL decisions, recovery time, tested key-copy identity, and failed-key/corruption behavior. No sensitive secrets in the record. Do not delete older backup points merely because one drill passed.

**Not yet verified:** physically independent recovery machine, externally stored ciphertext, actual private-key custody/recovery, re-key/rotation, Railway backup, write fencing of every worker, restore time objectives. No production RPO/RTO or public deployment approval follows from this document.

## Stop conditions

Stop without modifying source data if any of the following occurs: private key lost or leaked, unknown provenance of the encrypted snapshot, hash mismatch, failed decrypt/restore, different schema/layout than the chosen restore tooling, unexpected cloud synchronization, insufficient disk or absent operator approval. Escalate and preserve both the original snapshot and encryption artifacts; do not replace or discard them.

After a real **nonproduction** drill, record which machine/environment, which source archive format, what was verified, and which blockers remain. Only then can production recovery design be assessed.
