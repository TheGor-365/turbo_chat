# Gate 1 checkpoint — historical message focus and unread counts (2026-11-05)

## Proven local acceptance
- User reported typing indicator **works** in the normal/incognito two-browser local scenario after `git pull --ff-only`, `yarn build` and `docker compose restart web`.
- User performed the update from `4ca1fad` to `65f927f` with a fast-forward; `db/schema.rb` was already locally modified and is **not** changed in those commits. Owner saved a local patch to `~/turbo_chat_schema_backup_2026-11-05.patch` before pulling. Do not remove this patch or reset their local schema.
- On `65f927f`, GitHub Actions Rails/Chrome, Docker Compose smoke and Security audit all completed **successfully**.

## Next owner-local acceptance (pending)
- Search within DM `/rooms/1` for the known text `nice`, then click `Open message`, verify the chosen hit and `Return to latest messages`.
- Then verify inbox `All/Unread` behavior and cross-browser read acknowledgement. User has not reported these results yet.

## Independent bounded fix in Draft PR #2
- Audit found that opening `/rooms/:id?focus=older_id` could cause the `room-read` Stimulus controller to mark only the *old* rendered window as read, then immediately remove the entire unread sidebar badge—even though newer unread messages remained in the database.
- `app/views/rooms/index.html.erb` declares `data-room-read-history-focus-value` based on resolved authorized `@focused_message`.
- `app/javascript/controllers/room_read_controller.js` skips read acknowledgements for that bounded historical focus window. Live/latest view retains the existing read behavior.
- `test/system/chat_realtime_system_test.rb` adds real Chrome regression proving historical open does not advance the read cursor or visually clear unread; returning to latest does acknowledge read.
- Commits `139b2eb`, `67e8eff`, `d637669` in Draft PR #2. **CI status for new HEAD must be verified; do not claim green before checks complete.**

## Boundaries
- No DB migrations/schema changes, secrets, paid services, production Railway changes, merge to main, or public launch.
- Gate 1 remainder: reliable per-user unread updates across tabs, presence with TTL (current neutral indicator is intentionally not a real online signal), in-app notifications, reconnect UX, member/privacy settings.
