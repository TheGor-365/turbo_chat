# CAREER / Turbo Chat — Gate 1 DM Presence with Redis TTL (2026-11-05)

## Owner acceptance from latest conversation
- Owner confirms **Live Unread works** locally after `a5cb4a6` pull, JS build and Docker restart. This closes All/Unread cross-tab user acceptance.
- Previously confirmed locally: private DM typing, live search, scoped historical navigation with smooth in-pane focus/return.
- Visual design requirement: future UI/UX must be compact, contextual, precise, and dynamic — **not** a dashboard full of persistent buttons. This stage adds one minimal status line only.

## Presence implementation in Draft PR #2
- `PresenceRegistry`: Redis-scoped room/user sorted sets for multiple server-generated per-connection tokens, atomic Lua touch/remove/status with 45-second TTL and 12-second client heartbeat. Active visible sessions win over away; when no fresh sessions remain status is offline. No writes to persisted `users.status`, no stale-green values across reconnects.
- `RoomPresenceChannel`: ActionCable subscription requires current Warden user and *current private-room membership*, creates server-only random token, checks membership at each heartbeat, throttles, cleans up on unsubscribe. Only recipient-specific streams for the two DM members; broadcast **only** `{type:"presence_changed"}`, never draft content, credentials, global user lists or an arbitrary user_id.
- `GET /rooms/:id/presence`: authenticated + private room membership, resolves the **other participant** server-side. `Cache-Control: private, no-store`, response `{status:"online|away|offline"}`; Redis failure yields unavailable status (not fake online).
- `peer_presence_controller.js`: visible/hidden heartbeat, live invalidation fetch, 15-second status reconciliation for crashed/tab-sleep channels, reconnect, offline/unavailable safe fallback.
- Only the **open private DM** gets one small status dot + accessible label under its heading. Directory and public rooms still use neutral/unavailable dots; no global presence exposure.
- Unit/Redis tests cover multi-session close semantics, away, TTL expiry and isolated rooms/users; channel tests cover outsider/public-room rejection and payload privacy; HTTP tests cover ACL and forged peer ID; real Chrome test covers Alice sees Bob online, second Bob browser tab keeps it online, both close then status offline.
- Source docs (external verification): Redis EVAL contract at https://redis.io/docs/latest/commands/eval/ and ActionCable unsubscribed lifecycle at https://api.rubyonrails.org/v8.1/classes/ActionCable/Channel/Base.html .

## Limitations / unverified
- **CI on the newest HEAD needs explicit confirmation** before sending user update commands; owner-local acceptance is still pending.
- Room-scoped presence intentionally indicates connection to *that conversation*, not global last seen, which would require deliberate additional privacy settings.
- Durable user-configurable opt-out/visibility preferences (Gate 1 profile/privacy slice) not yet implemented. Do not market as complete privacy preferences or global presence.
- No DB migrations, no schema changes, no user status overwrite, no main merge, no new Railway app/deploy, no paid APIs.
- The owner keeps locally modified `db/schema.rb` backed up under `~/turbo_chat_schema_backup_2026-11-05.patch`; never reset/destroy it.

## Next owner-local acceptance
1. After green CI: `git pull --ff-only`; `yarn build && yarn build:css && docker compose restart web`.
2. Two Chrome contexts, `demo1` and `demo2` open same DM: demo1 should display `Online in this chat` while demo2 connected; after switching demo2 to the Conversations page, demo1 should display `Offline` (allow a few seconds for disconnect).
3. Then add a second demo2 tab still in DM: closing only one tab must not produce false Offline. If issue, inspect exact text and screenshot, not generic repeated setup.

## Pending Gate 1
- Account-level durable privacy/visibility settings, contextual in-app notifications and nuanced reconnect UX are still pending. Keep design-system overhaul in dedicated Gate 3.
