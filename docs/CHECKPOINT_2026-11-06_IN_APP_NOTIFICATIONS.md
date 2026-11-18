# CHECKPOINT — Persistent in-app notifications, Gate 1 — 2026-11-06

## Owner and baseline
- Owner confirmed local `git pull --ff-only` from `a5cb4a6` to `d57a4ca`, `yarn build`, `yarn build:css`, Docker web restart with no command error; no screenshot yet proving local DM Presence QA.
- Browser was restored after Linux reboot by deleting only stale Rails PID; existing PostgreSQL/Redis volumes preserved.
- Confirmed accepted before: DM typing, live search/history navigation and All/Unread.
- Owner requests continuing the agreed plan and eventual compact, contextual UI/UX, not a cockpit-like permanent toolbar.

## Delivered in Draft PR #2 — persistent *activity* events (not another unread-message engine)
- Migration `20261106130000_create_notifications.rb`: recipient, room, source message, event key, kind, read_at; composite unique `[user_id,event_key]`, unread/recent indexes and cascading foreign keys. No backfill of existing historical messages; events start for **new** incoming messages.
- `Notification` scopes enforce both the authenticated recipient and **current** public join/private participant membership, including after leave/revocation. No author self-notifications. Idempotent event key `message:ID`, constrained event type `new_message`, no message body copied to the event table.
- On message commit, record personal event for authorized recipients before emitting existing `RoomInboxChannel` invalidation. Deleting the source message cascades away notifications.
- Existing `RoomReadsController` monotonic cursor also marks corresponding personal events read **only through that message ID**. Manually marking an activity event read never advances/clears conversation unread cursor.
- `NotificationsController`: logged-in, current-member-only index (max 20/page), per-item and all read actions via POST, current-user IDOR protection, private/no-store index. Events show generic DM heading, `Member #ID`, relative time and an ACL-checked link to `?focus=:message_id`, never private message body in the event page.
- One small `Notifications` sidebar link and count; existing user-scoped ActionCable inbox invalidation refreshes that count in two tabs. No browser push, SMTP, external messages or paid APIs.
- Tests for create once, no self-events, source deletion, ACL after revoked membership, recipient-only read actions, no body/email leak, read cursor relationship and live badge change in the existing two-browser unread scenario. Eager-load author for bounded pagination.

## Explicitly not finished
- Mention-specific notification events need a trusted user handle/mention parser; `Member #ID` placeholders are not product-grade mention handles. No fictional mention support claimed.
- Durable notification preferences/mute/visibility controls still pending. No push/email; no browser Notification API.
- Notifications center itself is a normal Rails page, while the small room-sidebar badge refreshes live; true live content-refresh of the open notification-center page is not implemented in this slice.
- No user-local migration applied, no schema change on owner computer. **Owner had modified tracked `db/schema.rb`** before this work. Prior patch backup `~/turbo_chat_schema_backup_2026-11-05.patch`. Preserve user file and never reset or use Docker `down -v`.
- Only migration file added to GitHub branch; tracked `db/schema.rb` intentionally not regenerated or committed. Validate schema generation on CI and reconcile owner's local file before future commit/release.

## Verification and next
- Latest code requires **all CI on final HEAD** before local owner update.
- Owner next safe workflow after CI: backup current `db/schema.rb` and its git diff, then `git pull --ff-only`, `yarn build && yarn build:css && docker compose restart web`, `docker compose exec web bin/rails db:migrate` with backup preserved. If git pull or migration errors, stop, inspect, do not reset/rebuild volumes.
- Owner QA: Bob sends to Alice while Alice views Unread; Notifications count appears without F5; opening Notifications shows a generic event link, manual mark-read changes only event state, opening actual DM updates both event badge and conversation unread.
- Future: privacy toggles/room mute, mention handles, complete reconnect and attachment UX, then chosen UI concept in Gate 3.
