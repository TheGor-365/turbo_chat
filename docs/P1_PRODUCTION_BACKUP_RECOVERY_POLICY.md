# P1.4 — Production backup and disaster recovery policy (proposal, NOT deployed)

Date: 2026-11-07. Working branch: `feat/security-baseline-2026-11-03`, Draft PR #2.

## Evidence and status
- **Verified on owner Linux Mint (2026-11-07):** local backup, SHA-256 and archive validation, PostgreSQL 16 restore in disposable container, **8/8** Active Storage blob checksums, Rails boot on restored DB, HTTP authorizations for two existing room members, guest and stranger, four available media classes. The owner reported the full PASS output; see PR #2 checkpoint.
- **Verified in disposable GitHub Actions on 2026-11-12:** production-mode synthetic PostgreSQL 16 dump and private Active Storage archive during a stopped-web write-quiescent window, SHA-256 manifest and corruption-negative test, new isolated PostgreSQL restore, separate private media recovery, production Rails boot plus original two-room-member/outsider HTTP authorization, H5 revision integrity and attachment bytes: [CI PASS](https://github.com/TheGor-365/turbo_chat/actions/runs/43288845039). No real user data used; no external upload. See [scope and limitations](CI_BACKUP_RESTORE_2026-11-12.md).
- **Verified in disposable CI on 2026-11-12 (SHA `6446bd78`)**: `age` encrypt/decrypt of all three **synthetic** backup artifacts, ciphertext SHA-256, independent wrong-key and corrupted-ciphertext rejection, original plaintext integrity after decryption, and a second fresh PostgreSQL/media + production Rails/H5/ACL restore: [CI PASS](https://github.com/TheGor-365/turbo_chat/actions/runs/43291117129). The key existed only on a one-use CI runner, not with any user or operator backup.
- **Not verified:** **production** key escrow/decryption, offsite storage and recovery from an independent host, consistency with concurrent writes, scheduling, retention, rotation, Railway volumes, RPO/RTO, alerts or monitoring. No production readiness claim.

## Data inventory and recovery unit
A recoverable point is a **pair** of the PostgreSQL 16 consistent dump plus its corresponding private Active Storage tree. Message bodies, room membership and read cursors live in PostgreSQL; media/avatars are stored on private disk. Redis presence and transport are ephemeral and do not replace either source. Environment configuration, secrets, signing/encryption keys, deployment manifests and container image reference also require a separately protected operational recovery record; **never** put private keys inside the same uploaded backup archive.

The local dump is transactionally consistent, but database and private files are saved sequentially. An upload between these operations can produce a mismatch: production requires a *verified write-quiescent window* or an infrastructure-supported consistent snapshot. Do not run this local script in production.

## Initial service-level objectives — provisional, not commitments
- **RPO target:** <=24 hours after the first production release, only if automatic daily backup succeeds and has independent verification. Until then, RPO is **not established**.
- **RTO target:** <=4 hours for operator recovery after an isolated drill demonstrates that time end-to-end. Until then, RTO is **not established**.
- **Proposed schedule:** daily encrypted logical backup + private attachments; weekly full restore verification in an independent environment; monthly simulated host-loss restore with offsite ciphertext and an independently available recovery identity.
- **Proposed retention:** 7 daily, 4 weekly, 3 monthly recoverable points, subject to privacy obligations and actual storage costs. Each point includes both components. This is a planning target, **not an implemented deletion policy**.
- **Alert policy:** failure to create, encrypt, transfer or verify a backup, missing daily backup by SLA, offsite replication lag, excessive storage usage or key recovery failure must raise an operator-visible alert. No notification channel is currently configured.

## Encryption and key separation
Use `age` recipient-based encryption. The application host and backup exporter need only the **public recipient**, never a private age identity. Generate the key pair on a trusted device, store the secret key offline in an access-controlled location with a **second independent recovery copy**, and test decryption there before copying anything off-host. Do not post the private key, enter it into chat, commit it, or put it in shared AI-indexed Drive folders. Losing the private identity means loss of access to the encrypted backups. Changing recipients requires carefully planned re-encryption and verified new recovery, not deleting older keys first.

Supported **local only**, opt-in operations (do not execute until a public recipient and separately controlled key recovery exist):
```bash
bash bin/encrypt_local_backup.sh "/absolute/existing-backup" "/absolute/encrypted-output-parent" "age1PUBLIC_RECIPIENT" --encrypt-only
bash bin/verify_encrypted_backup.sh "/absolute/result-directory"
```
The encryptor revalidates the source, encrypts `database.dump`, `active_storage.tar.gz`, and `SHA256SUMS` independently, and writes hashes for encrypted files. It **retains the existing plaintext backup** and never uploads. An SHA check on ciphertext proves transfer integrity only; it is not a decrypt/restore test.

## Offsite destination requirements (NOT selected)
Before selecting a service: verify supported country/billing/account ownership, private storage access policies, at-rest encrypted-object handling, object versioning, locked retention/immutability, independent credential scope, egress/restore costs, and restore from an **independent machine**. Prefer an operator-owned storage bucket with versioned immutable backups and narrowly scoped upload-only credentials. Keeping all copies on the same Railway volume, local Docker host, or a synced public folder is not an offsite backup. No provider names, endpoints, costs or promised availability are asserted here.

## Gates for activation
1. **Partially met in CI only:** age encryption, decryption and isolated restoration on synthetic data passed. Still demonstrate *owner-controlled offline* decryption and independent key recovery on a nonproduction backup without exposing secret material.
2. Independently verify the actual destination's permissions, lifecycle policies, data residency and legal obligations. Use separate operator approval before uploading any private content or paying for storage.
3. Demonstrate a consistent DB+media snapshot under concurrent uploads and after forced restart.
4. Build idempotent scheduling, encrypted transfer, transfer integrity verification, retention **dry-run** with operator review, and operator alerts.
5. Run a cross-machine **offsite ciphertext -> offline decryption -> isolated Rails restore -> ACL/media** acceptance; record measured RPO/RTO.
6. Grant explicit release approval before any production deployment or `main` merge.

## Explicit safety rules
- No automatic deletion of old backups or encrypted archives until independently recoverable points are verified. No `docker compose down -v`, `db:reset`, `pg_restore --clean` on working DB or local `db/schema.rb` changes.
- Never store plaintext personal messages in a shared cloud/AI-indexed folder; never put private recovery keys on a web server.
- No remote upload, registration, purchase, connected Drive changes, GitHub secret setup or Railway changes performed in this P1.4 step.
