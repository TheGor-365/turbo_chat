# Turbo Chat — read/unread cursor vertical slice (2026-11-05)

Branch: `feat/security-baseline-2026-11-03`, draft PR #2. This is code work, **not** a production release or owner-local acceptance.

## What the change implements

- Additive `conversation_read_states` table keyed by unique (user, room), monotonic message ID cursor. Cursor is **not** a foreign key to a message because deleting older messages must not reset read progress.
- Authoritative CSRF-protected `POST /rooms/:id/read`, membership-checked. A cursor must resolve to an actual message in that authorized room. Idempotent and concurrency-safe SQL `UPDATE ... WHERE last_read_message_id < new_id`.
- One bounded sidebar group query computes counts of **other members' messages** newer than each cursor, for up to 50 visible public + 50 visible direct rooms. No globally shared unread feed or private email expansion.
- Small unread badges in DM and joined public room list; browser Stimulus controller only acknowledges an actually rendered message in a visible tab when the conversation is scrolled near the bottom. Offline failures leave unread state unchanged.
- Repair the legacy scroll controller's implicit `messages` global and mistyped DOM event so its observer preserves scroll position for new messages. It no longer forces a reader back to bottom while reading older history.
- Integration tests for sender-exclusion, public/private counts, monotonicity, nonmember and forged cross-room/invalid ID denial, guest redirects; model validation tests.

## Deliberate limits / next work

- Badges refresh on navigation and clear in the active room after successful acknowledgement. **Background realtime unread changes across inactive conversations are not yet implemented or claimed.** Planned private authenticated inbox events must not weaken current `RoomMessagesChannel` membership checks.
- WebSocket rejoin, replies/reactions acceptance, media playback and Linux Mint microphone remain their separate existing owner-local gates. Microphone diagnosis is deferred to final QA by owner request.
- `db/schema.rb` is deliberately untouched to preserve owner's **locally modified file**. Apply migration normally on the existing Docker dev DB after preserving its diff; never reset volumes.
- Do not merge `main`, create Railway resources, enable paid AI or publish screenshots without separate approval.
