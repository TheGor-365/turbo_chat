#!/usr/bin/env bash
# Explicit P1.3 Rails recovery acceptance. Never connects to live Compose DB.
set -euo pipefail
umask 077

if [[ $# -ne 2 || "$2" != "--isolated-app-acceptance" || "$1" != /* || ! -d "$1" ]]; then
  printf 'Usage: bash bin/restore_app_acceptance.sh /absolute/backup-dir --isolated-app-acceptance\n' >&2
  exit 2
fi

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)"
backup_dir="$(cd "$1" && pwd -P)"
if ! command -v docker >/dev/null || ! command -v python3 >/dev/null; then
  printf 'Requires Docker and Python 3.12+ for safe tar extraction.\n' >&2
  exit 1
fi
bash "$repo_root/bin/verify_local_backup.sh" "$backup_dir"

identifier="$(date -u +%s)-$RANDOM"
network="tc-restore-app-net-$identifier"
db="tc-restore-app-db-$identifier"
redis="tc-restore-app-redis-$identifier"
image="tc-restore-app:$identifier"
scratch="$(mktemp -d "${TMPDIR:-/tmp}/tc-app-acceptance.XXXXXXXX")"
network_created=0
image_created=0
db_created=0
redis_created=0

cleanup() {
  if [[ "$redis_created" == 1 ]]; then docker stop -t 3 "$redis" >/dev/null 2>&1 || true; fi
  if [[ "$db_created" == 1 ]]; then docker stop -t 3 "$db" >/dev/null 2>&1 || true; fi
  if [[ "$network_created" == 1 ]]; then docker network rm "$network" >/dev/null 2>&1 || true; fi
  if [[ "$image_created" == 1 ]]; then docker image rm "$image" >/dev/null 2>&1 || true; fi
  rm -rf -- "$scratch"
}
trap cleanup EXIT

# Validate and extract to a fresh private directory outside the checkout.
python3 - "$backup_dir/active_storage.tar.gz" "$scratch" <<'PY'
from pathlib import Path
import sys
import tarfile
archive, destination = sys.argv[1:]
root = Path(destination)
with tarfile.open(archive, "r:gz") as handle:
    members = handle.getmembers()
    if not members or len(members) > 200000:
        raise SystemExit("Refusing abnormal Active Storage archive")
    for member in members:
        path = Path(member.name)
        if (path.is_absolute() or ".." in path.parts or not path.parts or
                path.parts[0] != "storage" or
                not (member.isfile() or member.isdir())):
            raise SystemExit("Unsafe archive entry")
    handle.extractall(path=root, filter="data")
PY

docker network create --internal "$network" >/dev/null
network_created=1

docker run -d --rm --network "$network" --name "$db" \
  -e POSTGRES_PASSWORD=isolated-acceptance-only \
  -e POSTGRES_DB=postgres postgres:16-alpine >/dev/null
db_created=1
ready=0
for _ in $(seq 1 40); do
  if docker exec "$db" pg_isready -U postgres -d postgres >/dev/null 2>&1; then
    ready=1; break
  fi
  sleep 1
done
if [[ "$ready" != 1 ]]; then
  printf 'Isolated PostgreSQL not ready.\n' >&2
  exit 1
fi

# Restore only into the disposable database, never Docker Compose's volumes.
docker exec -i "$db" pg_restore -U postgres -d postgres \
  --create --no-owner --no-acl < "$backup_dir/database.dump" >/dev/null

docker run -d --rm --network "$network" --name "$redis" \
  redis:7-alpine redis-server --save "" --appendonly no >/dev/null
redis_created=1

printf 'Building a throwaway Rails image from the current checkout...\n'
docker build -f "$repo_root/Dockerfile.dev" -t "$image" "$repo_root" >/dev/null
image_created=1

# No host port, live container, Docker socket, existing DB volume or source storage.
docker run --rm --network "$network" \
  -e RAILS_ENV=development \
  -e PGHOST="$db" -e PGPORT=5432 \
  -e PGUSER=postgres -e PGPASSWORD=isolated-acceptance-only \
  -e REDIS_URL="redis://$redis:6379/1" \
  -e TURBO_CHAT_ISOLATED_RECOVERY=1 \
  --read-only --tmpfs /tmp:rw,nosuid,nodev,size=128m \
  --tmpfs /app/tmp:rw,nosuid,nodev,size=128m \
  --tmpfs /app/log:rw,nosuid,nodev,size=16m \
  -v "$scratch/storage:/app/storage:ro" \
  "$image" bin/rails runner script/isolated_restore_probe.rb

printf 'PASS: disposable Rails app booted with recovered database/files; HTTP ACL checked.\n'
printf 'Production recovery and RPO/RTO remain unverified.\n'
