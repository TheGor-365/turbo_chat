#!/usr/bin/env bash
# Explicit local recovery drill; never touches the developer PostgreSQL volume.
set -euo pipefail
umask 077

if [[ $# -ne 2 || "$2" != "--isolated-restore-only" || "$1" != /* ]]; then
  printf 'Usage: bash bin/restore_drill_isolated.sh /absolute/backup-dir --isolated-restore-only\n' >&2
  exit 2
fi
backup_dir="$(cd "$1" && pwd -P)"
repo_root="$(cd "$(dirname "$0")/.." && pwd -P)"
for program in docker python3; do
  command -v "$program" >/dev/null || { printf 'Missing: %s\n' "$program" >&2; exit 1; }
done
bash "$repo_root/bin/verify_local_backup.sh" "$backup_dir"

container="tc-restore-drill-$(date -u +%s)-$RANDOM"
scratch="$(mktemp -d "${TMPDIR:-/tmp}/tc-restore.XXXXXXXX")"
started=0
cleanup() {
  if [[ "$started" == 1 ]]; then docker stop -t 3 "$container" >/dev/null 2>&1 || true; fi
  rm -rf -- "$scratch"
}
trap cleanup EXIT

# No published ports, networks, host mounts, or named volumes.
# --rm removes the image-defined anonymous Postgres volume on stop.
docker run --rm -d --network none --name "$container" \
  -e POSTGRES_PASSWORD=restore-drill-only \
  -e POSTGRES_DB=postgres postgres:16-alpine >/dev/null
started=1

ready=0
for _ in $(seq 1 35); do
  if docker exec "$container" pg_isready -U postgres -d postgres >/dev/null 2>&1; then
    ready=1; break
  fi
  sleep 1
done
if [[ "$ready" != 1 ]]; then printf 'Isolated database unavailable\n' >&2; exit 1; fi

# --create applies only inside the disposable, network-isolated container.
docker exec -i "$container" pg_restore -U postgres -d postgres \
  --create --no-owner --no-acl < "$backup_dir/database.dump" >/dev/null
docker exec "$container" psql -U postgres -d turbo_chat -At -F "$(printf '\t')" \
  -c "SELECT key, checksum FROM active_storage_blobs ORDER BY id;" > "$scratch/blobs.tsv"

python3 - "$backup_dir/active_storage.tar.gz" "$scratch" "$scratch/blobs.tsv" <<'PY'
import base64
import csv
import hashlib
from pathlib import Path
import sys
import tarfile

archive, destination, manifest = sys.argv[1:]
root = Path(destination)
with tarfile.open(archive, "r:gz") as handle:
    members = handle.getmembers()
    if not members or len(members) > 200000:
        raise SystemExit("Invalid archive manifest")
    for member in members:
        path = Path(member.name)
        if (path.is_absolute() or ".." in path.parts or not path.parts or
                path.parts[0] != "storage" or
                not (member.isfile() or member.isdir())):
            raise SystemExit("Unsafe archive member")
    handle.extractall(path=root, filter="data")

verified = 0
with open(manifest, encoding="utf-8", newline="") as stream:
    for key, checksum in csv.reader(stream, delimiter="\t"):
        if not key.isalnum():
            raise SystemExit("Invalid blob key in restored DB")
        file = root / "storage" / key[:2] / key[2:4] / key
        if not file.is_file():
            raise SystemExit("Restored blob is missing")
        actual = base64.b64encode(hashlib.md5(file.read_bytes()).digest()).decode("ascii")
        if actual != checksum:
            raise SystemExit("Blob checksum mismatch")
        verified += 1
print(f"Verified restored Active Storage blobs: {verified}")
PY

docker exec "$container" psql -U postgres -d turbo_chat -At -c \
  "SELECT 'Restored users=' || (SELECT count(*) FROM users) ||
  ', rooms=' || (SELECT count(*) FROM rooms) ||
  ', messages=' || (SELECT count(*) FROM messages) ||
  ', attachments=' || (SELECT count(*) FROM active_storage_attachments);"
printf 'PASS: isolated DB restore + attachment checksums; production recovery remains unverified.\n'
