# CAREER / Turbo Chat — Gate 1 per-conversation mute (2026-11-06)

## Confirmed owner evidence
- Owner on Linux Mint pulled `9dc1f8f`, `yarn build` and restarted `web` successfully. Screenshot of DM `/rooms/1` shows a newly sent voice message (less than a minute old), with an audio player displaying `0:00 / 0:00`. Message persistence is visible; audible playback/duration is **not independently confirmed**. Do not claim a playback fix, request a real playback test later.
- Previous Notifications table `20261106130000` was successfully migrated locally. Owner's tracked `db/schema.rb` was modified before these steps and is backed up as `/home/gor/turbo_chat_schema_pre_notifications_20261106_015215.rb` plus `.patch`. No changes to local schema or Docker in this phase.
- Confirmed by prior screenshots: private presence online and away. Offline/multi-tab owner QA pending.

## Changes in existing Draft PR #2
- New migration `20261106190000_create_conversation_notification_preferences.rb`: user+room+muted(boolean) + timestamps; unique index on pair; cascading FKs. No existing data touched and no historical backfill required. Default is notifications enabled for all members without preference row.
- `ConversationNotificationPreference.muted_for?` resolves personal, scoped flags. `Notification.record_message!` skips new events for muted recipient; messages, conversation unread cursor, ActionCable message delivery and other users' notifications are **unchanged**. Existing notifications remain in the activity history; unmute only affects future messages.
- `RoomNotificationPreferencesController#update` requires Devise authentication + *current room membership*, forces current_user ownership, accepts only the exact strings `true`/`false`, rate-limits writes, returns 403/400 for forbidden/invalid input. HTML redirects to the room; Turbo Stream replaces only the contextual preference control without full chat reload; personal response no-store.
- Compact `Mute alerts` / `Unmute alerts` button in the room header for DMs and joined public rooms. There is no global badge suppression, client-side secret state or browser/SMTP push.
- Model tests cover private/public rooms, one-sided mute, no event backfill, no altered unread state, uniqueness. Controller tests cover guest/outsider/revoked membership, forged user_id, strict values, one DB row, Turbo partial. Real Chrome test checks a muted message is delivered and still unread while notification count stays zero; after unmute subsequent message triggers the normal real-time badge.
- The existing full UI/UX redesign remains Gate 3; keep mute contextual and small rather than a dashboard of toggles.

## Current status and blockers
- Code committed to the same Draft PR branch. **Check final HEAD CI** before asking owner to pull or migrate; no claim of green status until verified. No merge, public deploy, new Railway resources, external APIs, or destructive operations.
- This is notification *event mute*, not DND scheduling, hard blocking/ignoring a contact, private presence controls, or browser notification opt-out. Those are separate future settings.
- Owner-local acceptance is still pending. No `db:migrate` or `db:schema:load` has been requested/performed for this **new** preference table.

## Next user-local task after green CI
1. Back up the *current* schema again (prior snapshot remains important) and stop only the web container. Do not run `down -v`, `db:reset` or reset the Git branch.
2. `git pull --ff-only`, compile CSS/JS, `docker compose run --rm --no-deps web bin/rails db:migrate`, then restart web. Inspect console output; if any error, stop.
3. In a DM as demo1, click Mute alerts then have demo2 send; verify delivery/unread but no new notification event. Unmute and repeat; verify badge. Capture one screenshot.

## Future
- Account privacy option for presence, genuine display names/settings, mention semantics and notification preferences beyond per-room mute.
- Separate media issue: ensure newly uploaded voice WebM plays with nonzero duration through real media play, inspect ffprobe/Range if not; current 0:00 screenshot is only a suspicion.
