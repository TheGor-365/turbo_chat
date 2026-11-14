# Turbo Chat: message reactions (2026-11-05)

## Previous local evidence
- User confirmed backend AddReplyToMessages migration completed successfully
  (20261105010000), Docker web UP and PostgreSQL/Redis healthy.
- **UI Reply itself has not yet been explicitly user-accepted**.
- User confirmed silent video sent; recipient poster rendered but movement
  was not independently verified; recipient UI showed HTTP sync reconnecting.
- Microphone Linux Mint hiss/input failure intentionally deferred until the
  final pre-release QA, per user instruction. Do not reopen now.
- User's locally modified db/schema.rb was preserved by git pull; this
  branch must not push generated schema.rb until reconciling their diff.

## Reactions vertical slice
- Add `message_reactions` join table, unique (message,user,emoji);
  only six whitelisted emoji, max one of each per user/message.
- Safe room-scoped create/delete endpoints, no author impersonation,
  no nonmember/cross-room or other user's reaction deletion.
- User-specific per-room Turbo replacements on create/delete via model
  after_commit; sender gets direct Turbo stream replacement even if
  WebSocket is reconnecting. Reactions are independent of message edits.
- Functional reaction picker and chip counts only; professional custom
  design remains a later explicit stage. No third-party emoji SDK.
- Tests: model authorization/duplicate/invalid emoji, controller
  authentication/IDOR/unique/turbo response and two authenticated
  Chrome sessions realtime update without F5.
- Migration only; no edits to db/schema.rb, no client data deletion,
  no merge to main, no Railway deployment or billable AI API.

## Owner next
After full GitHub Actions PASS, instruct user to save existing schema
diff, ff-only pull, `docker compose exec web bin/rails db:migrate`,
restart web and verify 👍 reaction from both accounts. Never reset
or force-remove user's local db/schema.rb.
