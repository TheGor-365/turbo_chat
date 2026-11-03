# Turbo Chat — realtime and DM security checkpoint (2026-11-04)

## Scope and verification
Working branch: `feat/security-baseline-2026-11-03`, PR #2 remains draft. Source main and Railway projects unchanged.

Verified CI: https://github.com/TheGor-365/turbo_chat/actions/runs/41723681615 — 33 Minitest cases, 71 assertions, no errors/failures/skips. Asset build and PostgreSQL initialization green.

## Implemented
- `RoomMessagesChannel` validates the actual current Warden/ActionCable user, live room membership, verified signed stream name and exact expected room+user stream identity; foreign-user signatures are rejected.
- Generic `Turbo::StreamsChannel` subscriptions now reject, closing the bypass of a custom channel by switching its name while replaying a signed token.
- Removed obsolete global `users`, `rooms` and `user_status` subscriptions from chat HTML.
- Room page subscribes through `RoomMessagesChannel` and includes room ID in its subscription attributes.
- Room leave removes membership and disconnects the user's live ActionCable connections to force reauthorization on reconnect.
- Direct message creation verifies the canonical two-user name, disallows public rooms with reserved `private_` prefix, uses a transaction and row lock to manage membership, checks for unexpected third participants and retries DB unique conflicts.
- User DM endpoint now always passes through the membership-ensuring constructor, not an unvalidated existing-room shortcut.
- Channel tests include legitimate member, nonmember, foreign-user signed token, invalid token, revoked former member and default Turbo channel replay.
- Model tests cover DM idempotence, reserved namespace, invalid name and third-member collision.
- Controller test verifies rendered room page uses only authorized channel.

## Not yet verified
- WebSocket handshake end-to-end with **two real browsers**, including serialization of `data-room-id` into channel params.
- Socket disconnect latency and queued delivery behavior under rapid leave/reconnect; remote disconnect affects **all** active chat tabs for the user.
- True concurrent parallel requests/transactions with separate DB connections and race stress.
- Non-HTTP membership changes (future admin removal) must call the same revocation mechanism.
- Remaining P0 work: uploads and storage provider exposure, rate limits, XSS/CSRF/session hardening, security scanners, supported stack upgrade.

## Decision
Do not merge or deploy publicly until real browser realtime acceptance and all critical P0 gates pass.
