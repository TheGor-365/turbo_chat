# Private-group GATE 1 — rollout and acceptance (2026-11-08)

## Purpose and boundaries

Real invite-only group conversations are distinct from existing canonical private 1-to-1 conversations and public rooms. This feature is **server-authorized membership**, not end-to-end encryption. No external AI, paid API, deployment, existing chat data reset or production user migration.

The change belongs only to Draft PR #2, branch `feat/security-baseline-2026-11-03`; `main` remains untouched.

## Backward-compatible data model

Additive migration `20261108110000_add_private_group_membership_and_invitations.rb`:
- `rooms.kind` has `public_room`, `direct_message`, `private_group`, and records are backfilled by the existing `is_private` flag. Existing canonical DMs and public rooms retain their original names, records, messages, attachments and memberships.
- `rooms.owner_id` is required for the new `private_group` kind only. Group rooms keep `is_private=true`, so existing room-level HTTP/media ACL stays member-based.
- `participants.group_role` is set to `owner` or `member` only in new private groups.
- New `private_group_invitations` records target **one authenticated user**, with a unique `(room_id, user_id)` index, explicit `pending/accepted/declined/revoked` status and database foreign keys/check constraints. Invitation is not participant membership. Acceptance grants access and advances the per-user read cursor to pre-join history.
- User-specific per-group read cursors and room notifications reuse existing secure services. Direct messages retain their existing two-participant canonical identifier and lock.

Do **not** edit `db/schema.rb` by hand, reset data, drop volumes, run `db:schema:load`, `db:reset`, `docker compose down -v`, or overwrite the owner's intentionally modified local schema.

## Access control

- New public groups cannot be created using the private-group API, and private groups never appear in public discovery, public Join or the 1-to-1 chat list.
- Only the owner may invite or remove a group member; only the exact invited account may Accept/Decline.
- Nonmembers and pending invitees cannot fetch group page, attachments/posters, message sync/search, read state, messages, notification/history URLs or subscribe to RoomMessagesChannel.
- Revocation destroys group membership and disconnects all old websocket connections for that account, forcing channel authorization again. Per-recipient message broadcasting queries actual current group participants. It does not delete the room's historical messages.
- Group pages do not start 1-to-1 typing or peer presence; DM-only HTTP and websocket presence/typing endpoints additionally require `direct_message?`.

## UI acceptance

1. Jack on `/rooms`: create a private group (e.g. `Project Circle`) in the **Private groups** section. The group should appear only in Private groups, not Explore public rooms or Private chats (1-to-1).
2. Inside the group, Jack can select Eric by displayed public label and press **Invite**. Eric on `/rooms` sees a private invitation with **Accept/Decline**. Before acceptance Eric must not open the group URL.
3. Eric Accepts: group appears under Private groups and group membership details; both can exchange messages. Jack may remove Eric, after which the direct group URL, sync and media are forbidden for Eric; group messages remain preserved for authorized members.

## Owner-local schema migration gate — READ ONLY FIRST

**Important:** user's local `db/schema.rb` is deliberately modified (`git status -sb` reports `M db/schema.rb`). Current GitHub `db/schema.rb` also starts from a historical 2023 schema while migrations define newer tables. Do not pull-and-run the live app's new code against unmigrated tables, or execute a database migration without first inspecting this local state.

Ask owner to run only read-only checks before any local migration:
```bash
git status -sb
git diff -- db/schema.rb
docker compose exec web bin/rails db:migrate:status
```
(The last command is status-only; if `web` is not running, report its exact error, do not recreate containers or reset data.) Review what the dirty schema actually represents, confirm pending versions, retain all rows/files and then prepare a controlled additive `db:migrate` step with schema backup/rollback plan. Never tell the owner to force-clean or discard that modified file to get a fast-forward.

## Release gates

- Every branch commit must have exact-HEAD Rails/Redis/Chrome and security and Docker-smoke CI green.
- Owner local post-migration acceptance is required before claiming feature deployed/locally working.
- Private-group group-role changes and nonmember auth denial must be covered with request, channel, browser and attachment tests.
- Main merge, Railway staging, paid AI and real-user launch require separate explicit owner authorization.

## Known future improvements

- Invitation search beyond initial bounded 30 visible public-label users.
- Owner transfer / multi-admin role policy, moderation, private group invitation expiration and abuse limits.
- UI role semantics and accessible mobile settings, group notifications/mention controls and realtime revocation stress tests.
- Per-room AI and billing only after independent opt-in/privacy/budget gates.
