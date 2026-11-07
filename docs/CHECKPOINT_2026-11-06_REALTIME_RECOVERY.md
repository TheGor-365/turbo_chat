# CHECKPOINT — Realtime recovery states and contextual new-message pill — 2026-11-06

## Owner evidence
- Linux Mint / Docker Compose local app restored after reboot. Earlier `web` failed due stale `/app/tmp/pids/server.pid`; user removed only stale PID and relaunched `web`. Screenshot shows `http://127.0.0.1:3000/rooms/1` with messages and `Live · WebSocket connected`.
- Local code previously `a5cb4a6`; later PR `dedfa0f` includes real private-DM presence TTL, all CI green, **owner-local presence QA still not completed**. Owner explicitly says continue development.
- Accepted from earlier: DM typing, live search/history navigation, and live All/Unread.
- Future Gate 3 visual requirement: compact, contextual, dynamic interface, no permanent giant control panel.

## Gate 1 realtime slice
- `scroll_controller.js`: count only newly **inserted direct message elements whose numeric IDs exceed the mounted snapshot**, and only while the user is not following the bottom. Exclude older pagination IDs, replacement reaction markup, and history-focus window. The existing floating latest pill now changes to `N new message(s)` and clears when reader reaches bottom/clicks latest. No forced scroll while reviewing history; preserve unsent draft.
- `rooms/index.html.erb`: accessible tiny label target inside the existing latest pill, no new toolbar.
- `realtime_health_controller.js`: distinct truthful `connecting/live/reconnecting/http-synced/offline/sync-failed` states; browser offline/online/visibility subscriptions, HTTP-catch-up after network return, abort pending HTTP sync on offline/disconnect, avoid misleading live status during failed HTTP sync or fake WebSocket connectivity, preserve composer draft. Offline is a browser hint; server reachability still only established by real connection/fetch.
- System tests added for Bob sending while Alice scrolled up (1 new pill, no scroll jump, draft retained, pill closes on latest) and simulated navigator offline/online events (status changes, retry, draft survives).
- No DB migrations, no schema.rb writes, no change to current Railway service, no main merge, no paid features.

## Verification and next steps
- Gate 1 chunk is committed on existing Draft PR #2; **CI status must be read from exact new HEAD before claiming PASS**.
- Owner-local `db/schema.rb` is modified. Preserve it and backup `~/turbo_chat_schema_backup_2026-11-05.patch`; no reset/restore/down -v.
- After green CI, owner can fast-forward once and run `yarn build && yarn build:css && docker compose restart web`; also test previously landed DM presence Online/Away/Offline with normal Chrome/incognito and two demo2 tabs, then message pill by scrolling up and sending from other user.
- Remaining Gate 1: durable user preferences and privacy option, persistent notification center/read state/mute, robust room settings and attachment UX. These need a schema-controlled change separately; don't silently overwrite owner's modified schema.
