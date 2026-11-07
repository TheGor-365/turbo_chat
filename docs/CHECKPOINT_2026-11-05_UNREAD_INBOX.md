# Turbo Chat — unread inbox filter checkpoint (2026-11-05)

## Source of truth
- Existing draft PR: https://github.com/TheGor-365/turbo_chat/pull/2
- Working branch: `feat/security-baseline-2026-11-03`
- Feature commit: `8671d72385a37f866cf5708318e26704f1540f26`
- Parent HEAD before feature: `fb3674fb61610f11c0d19cac7e3fff48aeb3f0a7`
- No changes to `main`, Railway, any DB migration or `db/schema.rb`.

## Verified implementation
- Added `All / Unread` navigation for both authorized direct-message and joined public-room sidebar collections.
- Reused `ConversationReadState` and existing grouped unread count query, filtering the bounded 50+50 visible room collections; no duplicate cursor or global message-level read flag.
- Filter can be applied while viewing an active conversation; matching empty states are presented.
- Added request tests for per-user read status, authorized DM/public-room isolation, active conversation, all/unread navigation, and read acknowledgements.
- Existing membership authorization remains in controllers/model scopes, not just CSS.

## GitHub CI — PASS for feature commit
- Rails + Redis + Chrome: https://github.com/TheGor-365/turbo_chat/actions/runs/42037167850
- Docker Compose smoke: https://github.com/TheGor-365/turbo_chat/actions/runs/42037167903
- Ruby/JS security audit: https://github.com/TheGor-365/turbo_chat/actions/runs/42037167912
- All three workflow runs concluded SUCCESS; detailed test counts for this SHA should be taken from the run logs, not copied from earlier commits.

## Explicitly pending — do not overclaim
- Owner-local browser typing indicator acceptance: **NOT VERIFIED**. Last owner's local build and restart were on `4ca1fad`; local `db/schema.rb` is modified and MUST be preserved.
- Owner-local authorized room search-to-history and unread UX: **NOT VERIFIED**; Chrome system search and typing passed on preceding CI baseline.
- This first inbox filter is navigation-based, **not live global inbox updates**. It filters the first 50 visible DM and 50 joined public rooms. Complete paging, cross-tab unread synchronization, realtime global badges, mute and notification center remain in Gate 1.
- Presence with TTL, per-user notifications, profile/email privacy, AI consent, premium UI/UX, production image/storage/backups, new Railway demo and public screenshots are **NOT DONE**.
- Linux Mint microphone investigation intentionally deferred until final pre-release QA by owner.

## Next
1. Owner checks typing in two currently open browser sessions: type a draft in demo1; demo2 indicator appears without F5; clear draft; indicator disappears.
2. Owner checks search of old message with `focus` navigation, then unread display; report actual result, no retest of accepted Reply/Reactions without regression.
3. Independently implement the next small Gate 1 scoped feature and preserve existing DB/schema state. Do not merge PR or create paid/public resources without explicit approval.
