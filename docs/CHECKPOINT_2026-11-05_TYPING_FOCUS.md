# Checkpoint: typing indicator focus-loss behavior — 2026-11-05

## User evidence
- User tested the existing local application in normal Chrome and incognito as two authenticated demo participants on `/rooms/1`.
- The recipient did not see the typing indicator in sequential screenshots. Both pages displayed the independent "Live · WebSocket connected" messages stream.
- Recipient browser console returned `document.querySelector("#single_room")?.dataset.typingIndicatorConnected === "true"`, confirming the recipient's separate RoomTypingChannel subscription was connected.
- That value does **not** verify whether sender emitted `typing` or recipient received the event. Sender subscription and exact transport logs were not collected.
- Existing browser system tests validated cross-session typing in CI, but the user's manual focus-switch case had no regression coverage.

## Audited behavior and bounded fix
- The composer previously bound `blur->typing-indicator#stopTyping`. Switching from sender's active composer to the recipient window caused `stopped` to be sent immediately. Visibility changes had the same effect.
- `app/views/layouts/_new_message_form.html.erb`: remove the immediate `blur` stop action. Keep the explicit submit stop and the input action.
- `app/javascript/controllers/typing_indicator_controller.js`: on document becoming hidden, clear local received typing text but allow the pre-existing 3-second idle timer to send `stopped`. Receiving clients still have an independent 4.5-second stale-indicator expiry.
- `test/system/chat_realtime_system_test.rb`: assert the recipient still briefly sees the typing indicator immediately after the sender's input loses focus, and continues to verify clearing the draft hides it.
- Commits: `827e0bd`, `09948fa`, `c526916` on the existing Draft PR #2.
- No change to message persistence, private room permissions, typed text payloads, database schema, or Railway.

## Remaining acceptance
- New-HEAD CI status must be checked; do not infer success from earlier commits.
- User's local worktree still needs a safe fast-forward and client bundle rebuild. **Preserve their locally modified `db/schema.rb`**; no checkout/restore/reset or destructive commands.
- Re-test in two Chrome windows visible concurrently; new behavior provides a short 3-second grace after focus loss, not a perpetual indicator.
- If the receiver still never sees typing, inspect sender `data-typing-indicator-connected` and browser console/ActionCable events, then trace sender perform → authenticated channel → recipient stream. Do not claim the transport bug fixed without owner acceptance.

## Boundaries
- Draft PR #2 only; do not merge, deploy, launch publicly, pay for external resources, or alter the user's local schema.
