#!/usr/bin/env bash
# H3g.2: no-write readiness check against the ALREADY RUNNING local Rails app.
# Never prints API keys, messages, usernames, emails, or private text.
set -euo pipefail
if [[ $# -ne 2 || "$1" != "--read-only" || ! "$2" =~ ^[1-9][0-9]*$ ]]; then
  printf 'Usage: bash bin/h3g_live_readiness.sh --read-only ROOM_ID\n' >&2
  exit 2
fi

root="$(cd "$(dirname "$0")/.." && pwd -P)"
cd "$root"

if [[ "$(git branch --show-current)" != "feat/security-baseline-2026-11-03" ]]; then
  printf 'BLOCKED: expected H3g development branch.\n' >&2
  exit 2
fi
if ! docker compose ps --status running --services | grep -qx web; then
  printf 'BLOCKED: existing Rails web container is not running. No services started.\n' >&2
  exit 3
fi

docker compose exec -T -e "H3G_READINESS_ROOM_ID=$2" web bin/rails runner '
  id = Integer(ENV.fetch("H3G_READINESS_ROOM_ID"))
  puts "rails_env=#{Rails.env}"
  puts "manual_draft_grok_enabled=#{AiWorkspace::ManualDraftGeneration.enabled?}"
  puts "context_reply_grok_enabled=#{AiWorkspace::ContextReplyGeneration.enabled?}"
  puts "context_tasks_grok_enabled=#{AiWorkspace::ContextTaskGeneration.enabled?}"
  puts "consent_table_present=#{AiRoomContextConsent.table_exists?}"

  room = Room.find_by(id: id)
  if !room
    puts "room_exists=false"
  else
    puts "room_exists=true"
    puts "room_private=#{room.is_private?}"
    member_ids = room.participants.distinct.pluck(:user_id)
    granted = AiRoomContextConsent
      .where(room_id: room.id, user_id: member_ids, revoked_at: nil)
      .where.not(granted_at: nil).count
    puts "member_count=#{member_ids.size}"
    puts "consented_count=#{granted}"
    puts "all_members_consented=#{room.is_private? &&
      member_ids.size.between?(2, AiWorkspace::RoomContextAccess::MAX_PARTICIPANTS) &&
      member_ids.size == granted}"
  end
'
