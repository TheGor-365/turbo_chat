# CAREER / Turbo Chat — Gate 1 live inbox handoff (2026-11-05)

## Owner-confirmed state
- Linux Mint owner fast-forwarded `67cfba2 → 620d4bd`, successfully ran `yarn build`, `yarn build:css` and `docker compose restart web`.
- Screenshot evidence: searching `nice`, opening `/rooms/1?focus=8`, targeted highlight visible, whole-page header stable, clear Return to latest and floating Latest messages controls; owner states this now **works normally**. **Search Navigation = owner PASS**.
- Important design requirement from owner: during later Gate 3 UI/UX, every control must be compact, precise, contextual and dynamic; avoid permanently showing an oversized "airplane cockpit" full of buttons. Do not prematurely redesign before visual concepts are approved.

## Gate 1: defect and implementation
- Existing `ConversationReadState` is already a per-user, monotonic, room-authorized read cursor; `All/Unread` filters already exist. Do not recreate models or change database schema.
- Defect: unread badges and lists were server-rendered at page load, but did not update across other tabs/sessions when a member sends/deletes a message or reads a conversation.
- `RoomInboxChannel`: Warden-authenticated personal ActionCable stream, never accepts a client-supplied recipient/room ID, broadcasts **only** `{type: "changed"}`; no message text or peer identity in the WebSocket payload.
- `RoomsController#inbox`, GET `/rooms/inbox`: authenticated, private/no-store, server-authoritative snapshot using the same read-state count and room ACL as the normal page, with shared partials for direct/public lists. No arbitrary user_id override.
- `inbox_sync_controller.js`: subscribes to the user channel, fetches/reconciles the authorized lists on signal, reconnect, browser focus and visibility; aborts superseded HTTP requests, preserves the current All/Unread filter, keeps cached UI if temporarily offline.
- Signal producers: committed message create/delete to current authorized room recipients, successful read acknowledgement to the reader's other tabs, public room join/leave, DM start. Reorder is supplied by the existing last_message_at-sort.
- Existing regular `room-read` controller continues to acknowledge only visible live/latest messages; historical `?focus=N` does **not** inadvertently clear newer unread.
- Added unit channel tests for user isolation and body-free events, controller test for private snapshot and unauthorized user query, and real Chrome scenario: Alice Unread list, Bob sends, badge appears without reload, Alice reads in a second tab, badge disappears in original tab.
- Existing Railway/public deployment/main remain untouched. No DB migrations, no paid services. Local `db/schema.rb` was modified before this work and must remain untouched; owner saved `~/turbo_chat_schema_backup_2026-11-05.patch`.

## Verification / unfinished
- **CI for final HEAD must be checked**. Do not claim Rails/Chrome, Docker or audit green before final workflow conclusions.
- Owner-local test only after green CI: `git pull --ff-only`; `yarn build && docker compose restart web` (no CSS change); open normal Chrome as Alice on Unread inbox, incognito as Bob, send a message and verify Alice badge appears; have Alice read in second tab and verify the first tab clears automatically.
- Next Gate 1 beyond this bounded fix: robust read semantics for edits/deletes/mute/leave and reconnect; then presence with TTL and in-app notifications. Gate 3 visual concept selection separately.
