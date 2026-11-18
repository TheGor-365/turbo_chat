#!/usr/bin/env bash
# Read-only integrity validation for a LOCAL backup created by backup_local.sh.
# It never extracts archives, writes database rows, or touches active storage.
set -euo pipefail
umask 077

if [[ $# -ne 1 || ! -d "${1:-}" ]]; then
  printf 'Usage: bash bin/verify_local_backup.sh /absolute/path/to/turbo-chat-backup\n' >&2
  exit 2
fi

source_dir="$1"
if [[ "$source_dir" != /* ]]; then
  printf 'The backup path must be absolute.\n' >&2
  exit 2
fi
source_dir="$(cd "$source_dir" && pwd -P)"

for file in database.dump active_storage.tar.gz SHA256SUMS; do
  if [[ ! -f "$source_dir/$file" || -L "$source_dir/$file" ]]; then
    printf 'Missing or symlinked required backup file: %s\n' "$file" >&2
    exit 1
  fi
done

(
  cd "$source_dir"
  sha256sum --check --status SHA256SUMS
)

if ! tar -tzf "$source_dir/active_storage.tar.gz" > /dev/null; then
  printf 'Invalid compressed Active Storage archive.\n' >&2
  exit 1
fi

# pg_restore --list reads only archive metadata. It does NOT restore rows.
if command -v pg_restore >/dev/null 2>&1; then
  pg_restore --list "$source_dir/database.dump" > /dev/null
elif command -v docker >/dev/null 2>&1; then
  repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)"
  (
    cd "$repo_root"
    docker compose exec -T db pg_restore --list < "$source_dir/database.dump" > /dev/null
  )
else
  printf 'PostgreSQL pg_restore or local Docker Compose is required for dump metadata validation.\n' >&2
  exit 1
fi

printf 'PASS: SHA-256, PostgreSQL dump structure and Active Storage gzip/tar integrity.\n'
printf 'This is NOT a restore test or a guarantee of application-level recovery.\n'
