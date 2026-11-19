#!/usr/bin/env bash
# Read-only preflight for H3g consent migration. No DB writes, file deletion,
# container startup/restart, schema generation, network export or secrets.
set -euo pipefail
if [[ "$#" -ne 1 || "$1" != "--read-only" ]]; then
  printf 'Usage: bash bin/h3g_schema_preflight.sh --read-only\n' >&2
  exit 2
fi
root="$(cd "$(dirname "$0")/.." && pwd -P)"
cd "$root"
branch="$(git branch --show-current)"
if [[ "$branch" != "feat/security-baseline-2026-11-03" ]]; then
  printf 'BLOCKED: wrong branch %s\n' "$branch" >&2
  exit 2
fi
if [[ ! -f db/migrate/20261110200000_create_ai_room_context_consents.rb ||
      ! -f db/schema.rb ]]; then
  printf 'BLOCKED: migration or current local schema file missing.\n' >&2
  exit 2
fi
printf 'READ-ONLY H3g local preflight; branch %s, HEAD %s\n' "$branch" "$(git rev-parse --short HEAD)"
printf 'Local schema status:\n'
git status --short -- db/schema.rb
printf 'Local schema diff summary:\n'
git diff --stat HEAD -- db/schema.rb
printf 'Tracked schema header (not actual DB schema):\n'
grep -m1 'ActiveRecord::Schema\[' db/schema.rb || true
if ! docker compose ps --status running --services | grep -qx db; then
  printf 'BLOCKED: local DB container is not running. No services started.\n' >&2
  exit 3
fi
# Read-only PostgreSQL transactions. Do not output personal/client data.
db_read() {
  docker compose exec -T db psql -U postgres -d turbo_chat \
    --no-psqlrc --tuples-only --no-align --set=ON_ERROR_STOP=1 \
    --command="BEGIN READ ONLY; $1 COMMIT;"
}
result_table="$(db_read "SELECT CASE WHEN to_regclass('public.ai_room_context_consents') IS NULL THEN 'absent' ELSE 'present' END;")"
result_migration="$(db_read "SELECT CASE WHEN EXISTS (SELECT 1 FROM public.schema_migrations WHERE version = '20261110200000') THEN 'applied' ELSE 'pending' END;")"
table="$(printf '%s\n' "$result_table" | grep -Ex 'absent|present' | tail -1)"
migration="$(printf '%s\n' "$result_migration" | grep -Ex 'applied|pending' | tail -1)"
printf 'Existing PostgreSQL: consent table=%s, migration=%s\n' "$table" "$migration"
if [[ "$table" == "present" && "$migration" == "pending" ]] ||
   [[ "$table" == "absent" && "$migration" == "applied" ]]; then
  printf 'BLOCKED: migration history/table mismatch. Investigate; do not migrate.\n' >&2
  exit 4
fi
if [[ "$migration" == "pending" ]]; then
  printf 'PRECHECK PASS: migration pending. A separate verified private backup is mandatory before applying it.\n'
else
  printf 'PRECHECK PASS: migration appears applied; check local schema diff before any restart.\n'
fi
printf 'No writes or containers changed by this preflight.\n'
