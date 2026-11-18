# Turbo Chat — presence truthfulness checkpoint (2026-11-05)

## Scope
Draft PR #2, branch `feat/security-baseline-2026-11-03`. Incremental Gate 1 remediation, not a full presence implementation.

## Verified source changes
- Removed `RoomsController#set_status` and its before-action that marked every room visit `online` without connection lifetime or heartbeat evidence.
- `users/_status` renders a neutral "Presence unavailable" indicator instead of representing persisted `online`/`away` as current live connection state.
- Added request regression test that room index/show do not change a user's offline status and do not render a green presence dot.
- No migrations, Active Storage changes, local `db/schema.rb` changes, Railway operations, paid API calls, or `main` merge.

## Explicit limitations
- **Not implemented:** heartbeat, disconnect tracking, Redis TTL/multi-tab presence, privacy settings, authorized audience broadcasts. Existing persisted status enum is not a trustworthy live signal.
- **Owner local:** typing indicator and message search-to-history acceptance pending; last confirmed Linux build was `4ca1fad`, with modified `db/schema.rb`. Do not reset it.
- **CI:** new commits require fresh checks on latest branch HEAD; do not substitute earlier successful run numbers.
- Search and per-user read state already exist; do not recreate their schema.

## Next engineering slice
Implement scoped, expiring, multi-session presence with privacy and tests. This neutral state is an interim truthful UI, not the finished feature.
