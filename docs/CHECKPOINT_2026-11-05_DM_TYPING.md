# Turbo Chat — private typing indicator slice, 2026-11-05

## Owner-local evidence carried forward
- Local Fast-forward to 728d533, `yarn build` PASS, existing Docker web restarted without DB reset.
- Two screenshots show `demo2` sent the text `nice` with the quoted `demo1` media attachment visible in **both sessions**; `Live · WebSocket connected` in both windows. Reply local visible acceptance; user did not explicitly establish no-F5 for this specific screenshot.
- Message search field appears. Owner-local actual search results/old-message navigation not yet tested.

## New feature
- Ephemeral **DM-only typing status** delivered through a dedicated `RoomTypingChannel`, independent of the existing signed Turbo message stream.
- Server authorizes private room membership on subscribe and again for each action; canonical sender from the ActionCable session; recipients only registered private-room participants; client-supplied `room_id`, `user_id` and text are never echoed. Throttled 60 typing events per user/room per minute.
- Stimulus signals at most once per 2.5 seconds while drafting, sends a stop when emptied/blurred/submitted, and expires incoming display after 4.5 seconds on disconnect/crash. No message text, key presses, offline presence, or typing history saved.
- Chrome two-session test plus ActionCable channel authorization, spoofing, membership-revocation and rate-limit tests.
- **Not implemented or claimed:** public room typing, user presence/away/offline TTL, system notifications, global unread live updates, opt-in AI gateway, approved premium UI/UX.
- No migration, secrets, new services, `db/schema.rb` writes, main merge, Railway changes or paid AI APIs.
