# Checkpoint — local boot + reaction reconciliation (2026-11-08)

- Owner Linux Mint: branch fast-forwarded from 774483a to 5d7cbf3, Docker Compose web started on 127.0.0.1:3000 with PostgreSQL and Redis healthy. Screenshots confirm Jack/Eric direct chat and preserved message history; Private groups create UI visible. This is NOT yet private-group invite/Accept/Remove acceptance.
- Owner explicitly requested deletion of the Google Drive master. Native Google Doc 1n6bFpwpD9ZWgE84fie_fXPDouz-orhHdfSPR_sBquK4 was successfully deleted; project checkpoints remain in GitHub. Historical Drive master hyperlinks are obsolete.
- Bug: HTTP recheck uses Message#updated_at; reaction additions/deletions did not alter it, so a disconnected user could have stale reaction chips indefinitely. MessageReaction after_commit now touches the parent message before its existing per-recipient broadcast; no DB migration, no new external services.
- Regression: request test verifies sync after adding emoji and after deleting an older emoji when a newer reaction remains. Chrome test removes the live room stream and exercises explicit Sync for both addition and removal.
- No destructive operations, paid AI, Railway deploy or main merge. Owner's intentionally modified local db/schema.rb, DB volumes and Active Storage must remain untouched.
- Next owner acceptance: Jack creates group and invites Eric; Eric's pending invite grants no access; Eric accepts; both chat; Jack removes Eric; former member cannot retrieve room or media. Check latest exact HEAD CI before owner pulls new commit.
