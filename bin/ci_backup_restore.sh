#!/usr/bin/env bash
set -Eeuo pipefail
umask 077

# This script only accepts synthetic CI fixtures from ci_production_smoke.
# It cannot operate against a developer workstation, Compose DB or Railway.
if [[ "${GITHUB_ACTIONS:-}" != "true" || -z "${RUNNER_TEMP:-}" ||
      -z "${GITHUB_RUN_ID:-}" || $# -ne 6 ]]; then
  echo "Refusing backup/restore outside the disposable GitHub Actions smoke" >&2
  exit 2
fi

source_db="$1"
source_storage="$(realpath "$2")"
image="$3"
room_id="$4"
document_id="$5"
attachment_id="$6"
expected_db="relay-smoke-$GITHUB_RUN_ID-${GITHUB_RUN_ATTEMPT:-1}-postgres"
if [[ "$source_db" != "$expected_db" ||
      "$source_storage" != "$RUNNER_TEMP"/relay-production-smoke.*/private ||
      ! -d "$source_storage" || "$image" != "turbo-chat:release-candidate" ||
      -z "${SECRET_KEY_BASE:-}" || -z "${RELAY_SMOKE_PASSWORD:-}" ]]; then
  echo "Refusing backup/restore: input is not a synthetic CI fixture" >&2
  exit 2
fi
for id in "$room_id" "$document_id" "$attachment_id"; do
  [[ "$id" =~ ^[1-9][0-9]*$ ]] || { echo "Invalid synthetic fixture ID" >&2; exit 2; }
done
docker inspect "$source_db" >/dev/null

scratch="$(mktemp -d "$RUNNER_TEMP/relay-restore.XXXXXXXX")"
backup="$scratch/backup"
restore_network=""
restore_db=""
restore_redis=""
restored_private=""
network_created=0
db_created=0
redis_created=0

cleanup_restore_case() {
  if [[ "$redis_created" == 1 ]]; then
    docker stop -t 2 "$restore_redis" >/dev/null 2>&1 || true
  fi
  if [[ "$db_created" == 1 ]]; then
    docker stop -t 2 "$restore_db" >/dev/null 2>&1 || true
  fi
  if [[ "$network_created" == 1 ]]; then
    docker network rm "$restore_network" >/dev/null 2>&1 || true
  fi
  # The production entrypoint chowns only the disposable restored media root.
  # Reset its ownership before CI runner cleanup; never modify source files.
  if [[ -n "$restored_private" && -d "$restored_private" ]]; then
    docker run --rm --network none --user 0:0 \
      -v "$restored_private:/target" --entrypoint chown "$image" \
      -R "$(id -u):$(id -g)" /target >/dev/null 2>&1 || true
  fi
  network_created=0
  db_created=0
  redis_created=0
  restore_network=""
  restore_db=""
  restore_redis=""
  restored_private=""
}
cleanup() {
  cleanup_restore_case
  rm -rf -- "$scratch"
}
trap cleanup EXIT
mkdir -p "$backup"

# The caller has already completed all fixture writes. It stops the source web
# process before this script runs. Refuse an inconsistent DB+media pair otherwise.
source_web="relay-smoke-$GITHUB_RUN_ID-${GITHUB_RUN_ATTEMPT:-1}-web"
running="$(docker inspect --format '{{.State.Running}}' "$source_web")"
[[ "$running" == "false" ]] || { echo "Refusing snapshot with a running source web process" >&2; exit 1; }

echo "Creating a read-only snapshot of disposable CI PostgreSQL and private media"
docker exec "$source_db" pg_dump -U postgres -d turbo_chat_pro \
  --format=custom --no-owner --no-acl > "$backup/database.dump"
docker exec -i "$source_db" pg_restore --list < "$backup/database.dump" >/dev/null

# Read the complete private mount as root in an unprivileged CI helper process;
# never chmod, chown or delete the source files. No network is provided.
docker run --rm --network none --user 0:0 \
  -v "$source_storage:/source:ro" --entrypoint tar "$image" \
  -czf - -C /source . > "$backup/active_storage.tar.gz"
tar -tzf "$backup/active_storage.tar.gz" >/dev/null
(
  cd "$backup"
  sha256sum database.dump active_storage.tar.gz > SHA256SUMS
  sha256sum --check --status SHA256SUMS
)

# Deliberately corrupt only a temporary COPY and prove checksum validation
# rejects it. The original backup remains byte-identical.
mkdir "$scratch/tampered"
cp "$backup/database.dump" "$backup/active_storage.tar.gz" \
  "$backup/SHA256SUMS" "$scratch/tampered/"
printf 'tamper' >> "$scratch/tampered/active_storage.tar.gz"
if ( cd "$scratch/tampered" && sha256sum --check --status SHA256SUMS ); then
  echo "FAIL: tampered private archive was accepted" >&2
  exit 1
fi
echo "Backup integrity and negative corruption gate: PASS"

# Every recovery is isolated: a distinct internal-only Docker network, fresh DB,
# Redis and media root. The first run tests plaintext recovery; the second
# repeats the ENTIRE Rails/ACL/content acceptance from decrypted ciphertext.
run_isolated_restore() {
  local recovery_kind="$1"
  local snapshot="$2"
  [[ "$recovery_kind" == "plain" || "$recovery_kind" == "age" ]] ||
    { echo "Unknown CI recovery kind" >&2; exit 2; }
  restore_network="relay-restore-$GITHUB_RUN_ID-${GITHUB_RUN_ATTEMPT:-1}-$recovery_kind"
  restore_db="$restore_network-postgres"
  restore_redis="$restore_network-redis"
  restored_private="$scratch/restored-private-$recovery_kind"
  mkdir -p "$restored_private"

# Restore to a NEW isolated Docker network, a NEW PostgreSQL instance and a
# DIFFERENT private media mount. None can connect to the original CI database.
docker network create --internal "$restore_network" >/dev/null
network_created=1
docker run -d --rm --name "$restore_db" --network "$restore_network" \
  -e POSTGRES_DB=turbo_chat_pro -e POSTGRES_PASSWORD=ci-disposable-restore-only \
  postgres:16-alpine >/dev/null
db_created=1
for attempt in $(seq 1 40); do
  if docker exec "$restore_db" pg_isready -U postgres -d turbo_chat_pro >/dev/null 2>&1; then break; fi
  sleep 2
done
docker exec "$restore_db" pg_isready -U postgres -d turbo_chat_pro
docker exec -i "$restore_db" pg_restore -U postgres -d turbo_chat_pro \
  --no-owner --no-acl < "$snapshot/database.dump"

# Archive was generated from synthetic CI bytes. Extract into a new directory
# only; never extract into the source mount or the repository.
docker run -i --rm --network none --user 0:0 \
  -v "$restored_private:/target" --entrypoint tar "$image" \
  -xzf - -C /target < "$snapshot/active_storage.tar.gz"
docker run -d --rm --name "$restore_redis" --network "$restore_network" \
  redis:7-alpine >/dev/null
redis_created=1

echo "Booting production Rails solely against restored CI DB and recovered media"
docker run -i --rm --network "$restore_network" \
  -e RAILS_ENV=production \
  -e PGHOST="$restore_db" -e PGPORT=5432 -e PGUSER=postgres \
  -e PGPASSWORD=ci-disposable-restore-only \
  -e REDIS_URL="redis://$restore_redis:6379/0" \
  -e SECRET_KEY_BASE \
  -e TURBO_CHAT_STORAGE_ROOT=/data/turbo-chat-private \
  -e RAILWAY_VOLUME_MOUNT_PATH=/data/turbo-chat-private \
  -e RAILWAY_VOLUME_NAME=ci-only-restored-volume \
  -e RELAY_CI_ISOLATED_RESTORE=1 \
  -e RELAY_SMOKE_PASSWORD \
  -e RELAY_CI_ROOM_ID="$room_id" \
  -e RELAY_CI_DOCUMENT_ID="$document_id" \
  -e RELAY_CI_ATTACHMENT_ID="$attachment_id" \
  -v "$restored_private:/data/turbo-chat-private" \
  "$image" bin/rails runner - <<'RUBY'
require "digest"
require "warden/test/helpers"
require "action_dispatch/testing/integration"

abort "Refusing non-isolated recovery" unless
  ENV["RELAY_CI_ISOLATED_RESTORE"] == "1" &&
  ENV.fetch("PGHOST", "").start_with?("relay-restore-") &&
  Rails.env.production?

def check(condition, label)
  abort "FAIL: #{label}" unless condition
end

owner = User.find_by!(email: "relay-ci-owner@example.test")
member = User.find_by!(email: "relay-ci-member@example.test")
outsider = User.find_by!(email: "relay-ci-outsider@example.test")
check([owner, member, outsider].all? { |user|
  user.valid_password?(ENV.fetch("RELAY_SMOKE_PASSWORD"))
}, "restored account authentication hashes")

room = Room.find(ENV.fetch("RELAY_CI_ROOM_ID").to_i)
document = AiDeliverable.find(ENV.fetch("RELAY_CI_DOCUMENT_ID").to_i)
attachment = ActiveStorage::Attachment.find(ENV.fetch("RELAY_CI_ATTACHMENT_ID").to_i)
check(room.participants.pluck(:user_id).sort == [owner.id, member.id].sort,
  "restored private membership")
check(room.accessible_to?(owner) && room.accessible_to?(member) &&
  !room.accessible_to?(outsider), "restored private room boundaries")
check(document.room_id == room.id && document.owner_id == owner.id,
  "restored H5 owner")
revision = document.latest_revision
check(revision.version == 1 && revision.body_markdown.include?("relay-ci-private-h5") &&
  revision.body_sha256 == Digest::SHA256.hexdigest(revision.body_markdown),
  "restored immutable H5 revision and SHA-256")
check(revision.source_message_ids.size == 1 &&
  room.messages.where(id: revision.source_message_ids, user_id: member.id).exists?,
  "restored H5 citation and source author")
AiWorkspace::RoomContextAccess.new.authorize!(room: room, actor: owner)

check(attachment.record_type == "Message" &&
  attachment.record.room_id == room.id &&
  attachment.blob.download == "relay-ci-secret-attachment\n",
  "restored permission-scoped attachment bytes")
standalone = ActiveStorage::Blob.find_by!(filename: "release-smoke-private.txt")
check(standalone.download == "relay-ci-private-media\n",
  "restored standalone private media bytes")
check(ActiveStorage::Blob.count >= 2, "restored blob inventory")

# Exercise Rails route permissions against recovered DB and storage. Warden
# test helpers impersonate only these disposable CI accounts; production
# login was independently tested by ci_production_smoke before snapshot.
class RecoveredAppProbe
  include Warden::Test::Helpers

  def session_for(user)
    Warden.test_reset!
    login_as(user, scope: :user) if user
    ActionDispatch::Integration::Session.new(Rails.application).tap do |session|
      session.host! "localhost"
      session.https!
    end
  end

  def assert_get(user, path, status, body_marker: nil)
    session = session_for(user)
    session.get(path)
    actual = session.response.status
    abort "FAIL: restored HTTP ACL #{status} expected, got #{actual}" unless actual == status
    if body_marker && !session.response.body.include?(body_marker)
      abort "FAIL: restored HTTP content marker unavailable"
    end
  end
end

Warden.test_mode!
begin
  probe = RecoveredAppProbe.new
  h5_path = "/rooms/#{room.id}/ai_deliverables/#{document.id}/export.md?version=1"
  media_path = "/chat-attachments/#{attachment.id}"
  probe.assert_get(owner, h5_path, 200, body_marker: "relay-ci-private-h5")
  probe.assert_get(member, h5_path, 404)
  probe.assert_get(outsider, h5_path, 403)
  probe.assert_get(owner, media_path, 200, body_marker: "relay-ci-secret-attachment")
  probe.assert_get(member, media_path, 200, body_marker: "relay-ci-secret-attachment")
  probe.assert_get(outsider, media_path, 404)
ensure
  Warden.test_reset!
end
puts "PASS: restored production Rails, original roles, H5 ACL/SHA, citations and private media"
RUBY
  echo "Independent CI $recovery_kind PostgreSQL, media and Rails ACL recovery: PASS"
  cleanup_restore_case
}

run_isolated_restore "plain" "$backup"

# Protect the temporary synthetic backup with an age X25519 recipient. Neither
# ciphertext nor CI logs contain a private identity. The identity resides in a
# separate restrictive directory on the one-use GitHub runner, never in Git,
# an uploaded artifact, Railway, shared Drive or production storage.
for command in age age-keygen python3; do
  command -v "$command" >/dev/null ||
    { echo "Missing CI encryption prerequisite: $command" >&2; exit 1; }
done
identity_dir="$scratch/recovery-identity"
encrypted="$scratch/encrypted-backup"
decrypted="$scratch/decrypted-backup"
mkdir -m 0700 "$identity_dir" "$encrypted" "$decrypted"

# Prevent key material and synthetic credentials from being printed to logs.
age-keygen -o "$identity_dir/recovery.txt" >/dev/null 2>&1
recipient="$(age-keygen -y "$identity_dir/recovery.txt")"
[[ "$recipient" == age1* ]] || { echo "No age public recipient" >&2; exit 1; }
for file in database.dump active_storage.tar.gz SHA256SUMS; do
  age -e -r "$recipient" -o "$encrypted/$file.age" "$backup/$file"
done
(
  cd "$encrypted"
  sha256sum database.dump.age active_storage.tar.gz.age SHA256SUMS.age > CIPHERTEXT_SHA256SUMS
  sha256sum --check --status CIPHERTEXT_SHA256SUMS
)
test ! -e "$encrypted/recovery.txt" ||
  { echo "FAIL: backup contains private identity" >&2; exit 1; }

# Prove that a DIFFERENT private identity cannot decrypt the backup.
age-keygen -o "$identity_dir/wrong.txt" >/dev/null 2>&1
if age -d -i "$identity_dir/wrong.txt" \
    -o "$scratch/incorrect-key-recovery.dump" "$encrypted/database.dump.age" \
    >/dev/null 2>&1; then
  echo "FAIL: ciphertext accepted the wrong age identity" >&2
  exit 1
fi
rm -f -- "$scratch/incorrect-key-recovery.dump"

# Mutate only a temporary COPY of one ciphertext and assert that age detects
# authenticated-encryption corruption, independently of the SHA manifest.
python3 - "$encrypted/active_storage.tar.gz.age" "$scratch/corrupted-media.age" <<'PY'
from pathlib import Path
import sys

data = bytearray(Path(sys.argv[1]).read_bytes())
if len(data) < 128:
    raise SystemExit("Abnormally short synthetic age ciphertext")
index = max(64, len(data) // 2)
data[index] ^= 0x01
Path(sys.argv[2]).write_bytes(data)
PY
if age -d -i "$identity_dir/recovery.txt" \
    -o "$scratch/rejected-media.tar.gz" "$scratch/corrupted-media.age" \
    >/dev/null 2>&1; then
  echo "FAIL: corrupted ciphertext was accepted by age" >&2
  exit 1
fi
rm -f -- "$scratch/rejected-media.tar.gz"
echo "Synthetic age encrypt, ciphertext SHA, wrong-key and tamper rejection: PASS"

# Decrypt all THREE protected artifacts into a directory distinct from the
# original plaintext snapshot. Compare bytes and validate the inner manifest
# before ever creating a second restored PostgreSQL instance.
for file in database.dump active_storage.tar.gz SHA256SUMS; do
  age -d -i "$identity_dir/recovery.txt" \
    -o "$decrypted/$file" "$encrypted/$file.age"
  cmp -s "$backup/$file" "$decrypted/$file" ||
    { echo "FAIL: decrypted $file differs from snapshot" >&2; exit 1; }
done
(
  cd "$decrypted"
  sha256sum --check --status SHA256SUMS
)
tar -tzf "$decrypted/active_storage.tar.gz" >/dev/null
docker exec -i "$source_db" pg_restore --list < "$decrypted/database.dump" >/dev/null
echo "Synthetic age decryption and original DB/media SHA manifest: PASS"

run_isolated_restore "age" "$decrypted"
echo "Disposable CI plaintext and age-decrypted independent production restores: PASS"
