#!/usr/bin/env bash
# Read-only ciphertext transfer integrity check; does not decrypt or ask for keys.
set -euo pipefail
if [[ $# -ne 1 || "${1:-}" != /* || ! -d "$1" ]]; then
  printf 'Usage: bash bin/verify_encrypted_backup.sh /absolute/encrypted-backup-dir\n' >&2
  exit 2
fi
directory="$(cd "$1" && pwd -P)"
for name in database.dump.age active_storage.tar.gz.age SHA256SUMS.age CIPHERTEXT_SHA256SUMS; do
  if [[ ! -f "$directory/$name" || -L "$directory/$name" ]]; then
    printf 'Missing or symlinked ciphertext component: %s\n' "$name" >&2
    exit 1
  fi
done
(
  cd "$directory"
  sha256sum --check --status CIPHERTEXT_SHA256SUMS
)
printf 'PASS: encrypted backup files match the ciphertext SHA-256 manifest.\n'
printf 'This does not validate decryption, private key custody or successful restoration.\n'
