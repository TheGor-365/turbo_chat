# GATE 1 — private-group Leave UI parity (2026-11-08)

## Owner-local acceptance evidence
Linux Mint screenshots show Jack creating Project Circle at /rooms/3, inviting Eric, Eric accepting, member count 2 and two-way messages ("hey") in the private group. Private room had no Leave control, unlike the public room sidebar. Pre-accept direct URL denial and post-Leave access revocation were not manually confirmed by owner.

## Fix
- Public joined-room and invite-only private group inbox now render one shared room row: conversation name, unread count, last activity and icon-only accessible Leave action, including shared CSS and focus/hover geometry.
- `DELETE /private_groups/:id/leave` checks current membership under the room row lock, removes only the member, not room/messages/attachments, invalidates the member's old ActionCable subscriptions and takes them back to inbox.
- For a departing owner, transactionally transfer `owner_id` and group role to the oldest remaining member; revoke any pending invitations authorized by the old owner. A sole owner cannot leave without first inviting and admitting another member. No ownerless group and no deletion.
- Public-room Leave and canonical 1:1 DMs are unchanged. Group members can be re-invited by the current owner. No schema migration.

## Regression / release gates
Integration tests cover member leave, attachment/history retention via existing ACL and unchanged message rows, owner transfer, pending-invite revocation, last-owner guard, outsider and non-group protection; Chrome tests assert shared icon and actual browser Leave after Accept.
Draft PR #2 only: no main merge, no Railway, no paid AI, no local DB/volume/storage cleanup. Owner-local app currently on `5d7cbf3`; the latest full branch HEAD must pass CI before pull and screenshot acceptance.
