#!/usr/bin/env bash
# Explicit, non-destructive backup of the LOCAL development stack only.
# Does not stop services, change schema, restore, deploy, or upload anything.
set -euo pipefail
umask 077

if [[ $# -ne 1 || -z "${1:-}" ]]; then
  printf 'Usage: bin/backup_local.sh /absolute/path/to/private-backup-directory\n' >&2
  exit 2
fi

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)"
backup_parent="$1"
if [[ "$backup_parent" != /* ]]; then
  printf 'Backup directory must be an absolute path outside the repository.\n' >&2
  exit 2
fi

mkdir -p -- "$backup_parent"
backup_parent="$(cd "$backup_parent" && pwd -P)"
case "$backup_parent/" in
  "$repo_root/"*) printf 'Refusing to store private data inside the repository.\n' >&2; exit 2 ;;
esac
if [[ "$backup_parent" == "/" ]]; then
  printf 'Refusing to store backups in the filesystem root.\n' >&2
  exit 2
fi

cd "$repo_root"
if ! docker compose ps --status running --services | grep -qx db; then
  printf 'The local PostgreSQL Compose service must already be running.\n' >&2
  exit 1
fi
if [[ ! -d storage ]]; then
  printf 'Local Active Storage directory is missing; not creating a partial backup.\n' >&2
  exit 1
fi

timestamp="$(date -u +%Y%m%dT%H%M%SZ)"
destination="$backup_parent/turbo-chat-$timestamp"
if [[ -e "$destination" ]]; then
  printf 'Backup destination already exists; refusing to overwrite: %s\n' "$destination" >&2
  exit 1
fi

temporary="$(mktemp -d "$backup_parent/.turbo-chat-partial.XXXXXXXX")"
cleanup() {
  if [[ -n "${temporary:-}" && -d "$temporary" ]]; then
    rm -rf -- "$temporary"
  fi
}
trap cleanup EXIT

# pg_dump creates a transactionally consistent DB snapshot while Rails runs.
# The local file archive is taken after the database dump; simultaneous uploads
# could make the two differ, so restore validation is still required.
docker compose exec -T db pg_dump -U postgres -d turbo_chat \
  --format=custom --no-owner --no-acl > "$temporary/database.dump"
docker compose exec -T db pg_restore --list < "$temporary/database.dump" > /dev/null

tar -czf "$temporary/active_storage.tar.gz" -C "$repo_root" storage
tar -tzf "$temporary/active_storage.tar.gz" > /dev/null

(
  cd "$temporary"
  sha256sum database.dump active_storage.tar.gz > SHA256SUMS
  sha256sum --check --status SHA256SUMS
)
printf 'Local development backup; private; not a verified restore.\n' > "$temporary/README.txt"
mv -- "$temporary" "$destination"
temporary=''
printf 'Created private backup: %s\n' "$destination"
printf 'Contains database.dump, active_storage.tar.gz and SHA256SUMS. Restore not yet validated.\n'
