# Turbo Chat — Gate 1: account privacy for DM presence (2026-11-06)

## Why this slice
- User wants a finished real-time messenger with compact contextual controls before the full Gate 3 premium UI/UX.
- DM Presence (Redis TTL 45 seconds, multi-session Online/Away/Offline) is implemented. User screenshot demonstrated Online and Away, but local multi-tab/Offline transitions remain separate QA.
- Privacy opt-out was outstanding and must be applied server-side, never only by hiding a green dot in JavaScript.

## Code in existing Draft PR #2
- Migration `20261106200000_add_share_presence_to_users.rb`: persisted boolean, NOT NULL, default true, preserving existing visible behavior.
- One small independent button under Devise account settings: `Appear offline` / `Show when active`; changes only current user's visibility, does not require their password or modify login email/profile. Authenticated CSRF-protected PATCH endpoint with rate limiting and exact boolean validation.
- On opt-out, persists value before clearing this user's Redis PresenceRegistry tokens in **each currently joined private room**, then emits only room/recipient-scoped `presence_changed` events so an open peer browser refreshes without F5. If Redis becomes unavailable, persisted flag still masks HTTP presence and prevents fresh ActionCable heartbeats.
- The private snapshot endpoint checks peer's persisted flag before returning Redis state; invisible members appear simply `offline`, never leaking the preference or peer email.
- Every ActionCable heartbeat reloads current user's flag and refuses to re-create presence while hidden, including stale tabs. Typing, messages, room unread, in-app notification mute, memberships and auth are unchanged.
- No global presence broadcast or public room tracking introduced.

## Verification required
- New controller tests: guest rejection, cannot change another user's flag, inputs strict, status masking, Redis cleanup across two browser tokens, settings labels.
- Channel test: pre-existing subscribed tab cannot restore visibility after opt-out.
- Real Chrome/Redis multi-tab test: Alice's chat remains open, account preference is changed in separate session, Bob sees offline without F5; returning to visible with a new heartbeat shows online.
- Verify all 3 GitHub Actions at **final HEAD** before any owner-local pull/migration; no claims of PASS without results.

## Local constraint and recovery
- Owner local branch `03b11a0`, new preference table migration `20261106190000` **not yet confirmed applied**. Owner ran `docker compose stop web`, then `docker compose run --rm --no-deps web bin/rails db:migrate`, which failed with `PG::ConnectionBad: could not translate host name \"db\" to address`. Subsequent `&& docker compose up -d web` did **not** execute; local web probably stopped, cannot inspect local host from GitHub.
- Correct immediate recovery: `docker compose up -d db redis && docker compose run --rm web bin/rails db:migrate && docker compose up -d web && docker compose ps`, verify HTTP. Never run `down -v`, `db:reset` or drop owner data.
- The owner has a locally modified tracked `db/schema.rb` with multiple backup snapshots. New migration is GitHub-only, not locally applied. Before any future pull and DB migration, preserve latest local schema/patch again.

## Deferred
- True account profile/display_name; email privacy in own sidebar; browser voice playback 0:00/0:00 unverified; DND, mention semantics, global notification preferences, full responsive UI/UX.
- No main merge, Railway change, public release or paid service.
