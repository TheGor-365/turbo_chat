# R1 — disposable synthetic backup and independent recovery acceptance

Date: 2026-11-12. Draft PR #2 / feature branch `feat/security-baseline-2026-11-03`.
Initial plaintext recovery evidence at SHA `998d85d03e9e639f1e689b11c27b11e79b2669a5`: [PASS](https://github.com/TheGor-365/turbo_chat/actions/runs/43288845039).
**Extended age encrypted recovery evidence** at SHA `6446bd78a89f6fb041eabcfa9936198d9c72d213`: [PASS](https://github.com/TheGor-365/turbo_chat/actions/runs/43291117129).

## What was actually tested

The workflow builds the production Docker image, migrates a **new empty** PostgreSQL 16 database and creates three synthetic users (document owner, private-room member and outsider), a private room, source message, H5 draft and two private media blobs.

After normal authentication, H5 access, media, consent and container-replacement smoke tests, CI **stops its own throwaway web container**. Only then does the CI-only script `bin/ci_backup_restore.sh`:

1. Capture `pg_dump -Fc` from the synthetic source database plus the complete private storage mount as `active_storage.tar.gz`.
2. Validate the dump's PostgreSQL archive structure, tar readability and a SHA-256 manifest for both artifacts.
3. Corrupt **only a temporary copy** of the media archive and verify that checksum validation rejects it.
4. Create a **different**, isolated Docker network, a fresh PostgreSQL 16 container, a fresh Redis, and a separate recovery media path. Restore DB and extracted files only there.
5. Boot the same production Rails image against that **restored** DB and mount. Verify persisted credentials as password hashes, room membership, H5 owner/revision body SHA-256 and source citation, exact private attachment bytes and standalone media bytes.
6. Exercise recovered Rails request authorization using synthetic users: H5 owner HTTP 200, another current member 404, outsider 403; private attachment HTTP 200 for members and 404 for outsider.
7. Stop and remove disposable CI containers/network and clean the temporary working directory. No source database or operator-local files are changed.

**Actual PASS:** checksum/corruption gates; independent PostgreSQL + file restore; Rails boot and recovered private ACL/content; complete CI cleanup. This verifies a recoverable **synthetic quiescent** snapshot in one GitHub-hosted runner.

## Extension: temporary age ciphertext, wrong-key and tamper-negative tests

At `6446bd78`, the same CI job installs the distribution-packaged `age` tool and, **after a completed plaintext restore**, creates an ephemeral age X25519 identity (private mode 0600 under a dedicated temporary folder) and obtains its public recipient without printing the private key. CI then:

1. Encrypts `database.dump`, `active_storage.tar.gz`, and `SHA256SUMS` independently to a separate ciphertext-only directory and computes `CIPHERTEXT_SHA256SUMS`. The private age identity is **not included** in the encrypted backup directory or uploaded anywhere.
2. Verifies SHA-256 over the three ciphertext files.
3. Generates a **different** temporary private identity and confirms decryption with that incorrect identity fails.
4. Flips a byte in a temporary copy of the encrypted media, confirming age authenticated decryption refuses the altered ciphertext.
5. Decrypts all three original encrypted artifacts to a **third**, fresh directory; compares every decrypted byte with the original snapshot, checks the original `SHA256SUMS` and validates the dump and tar structure.
6. Repeats **the entire independent restore** with a **second** fresh PostgreSQL 16, Redis and private media mount; boots production Rails and repeats role, H5 SHA/citations and exact attachment-byte/HTTP ACL acceptance.
7. Cleans up all disposable containers, networks, plaintext/ciphertext copies and the ephemeral key directories on the GitHub runner.

**Verified:** synthetic encryption and decryption, ciphertext integrity, wrong-key/tamper rejection, and **two complete separate recoveries**, the second from decrypted archive bytes. [CI logs](https://github.com/TheGor-365/turbo_chat/actions/runs/43291117129). These are one-runner tests, not a production offsite backup.

The script checks `GITHUB_ACTIONS`, `RUNNER_TEMP`, the expected synthetic container name, the temporary source mount path and fixed image name. It refuses workstation/Compose/Railway inputs. It is **not** a general-purpose production backup exporter.

## Explicit limits and remaining release gates

- No concurrent writes while snapshotting: CI stops its own web process. A real app needs an enforced write-quiescence mechanism or infrastructure-supported consistency for the DB+media pair.
- The CI extension uses temporary `age` ciphertext and disposable X25519 key material on the **same runner**. It does **not** verify operator-owned offline key escrow, independent recovery identity, real backup encryption or cross-machine decryption. No offsite upload or retained production artifact exists.
- Same CI machine/image is used for restore. This is not an independent machine or failure-domain drill, nor evidence of actual Railway volume persistence.
- Only synthetic data and small text media were tested here, not the complete multimedia/permission matrix from a real restored installation.
- No schedule, retention/rotation, alerting, backups for production, monitoring or measured RPO/RTO. No guarantee of customer-data restoration.
- No deletion of owner-local backups/volumes. **Do not use this CI test as authorization for Railway deployment, public signup, a production-data backup or a merge to `main`.**

Next gate: owner-controlled offline recovery identity, separately approved offsite storage, consistency under concurrent writes, and isolated cross-machine recovery using encrypted production-like data before any customer data is accepted.

Reference policy: [P1 production backup & disaster recovery proposal](P1_PRODUCTION_BACKUP_RECOVERY_POLICY.md).
