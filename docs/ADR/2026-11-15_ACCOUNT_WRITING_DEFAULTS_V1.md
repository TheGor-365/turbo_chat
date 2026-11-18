# Account Writing Defaults V1 — 2026-11-15

**Status:** Implemented in Draft PR #2, exact-SHA CI pending.
One new additive migration `20261115230000_create_ai_account_writing_preferences.rb`.
No changes to `db/schema.rb` are committed; owner's existing local changes
must be backed up and preserved. Local migration not applied by assistant.

## Inheritance and ownership

- Account defaults are one `AiAccountWritingPreference` per authenticated
  user, with allowlisted `profile_id, writing_style, language, tone`.
- Room-specific `AiRoomWritingPreference` rows (already implemented and
  locally migrated) win over the entire account snapshot; another room
  with no explicit row inherits account defaults. If neither exists, the
  established system default is used. Message-only overrides still win
  inside a single explicit generation, never writing account/room state.
- Existing prior room rows remain overrides. No silent mass migration or
  overwrites. Explicit room-level "Use account defaults" deletes **only**
  this member's room row and re-applies the account snapshot in-place without
  a full page reload, preserving an unsent draft.
- Legacy browser-local writing preferences remain a fallback only when
  neither a room nor account row is configured; device-local spellcheck is
  preserved when resetting a room. The server's row always overrides
  stale localStorage.
- Profile or manual style edits in a room create room overrides. Account
  writes never alter other users' settings or their existing room rows.
- Model and controller code reject keys other than the four allowlisted
  values and invalid profile/style combinations. Unique DB index on
  user_id, account member ownership, CSRF/Devise authentication,
  no-store cache policy, independent non-billing rate limits.

## UI

- Account Profile & Settings contains a **separate** form using
  native-backed Signal Deck dropdowns for profile, writing style,
  language and tone. Account save cannot trigger Devise password/profile
  changes.
- A selected account profile fills its style/tone; custom style clears
  profile ID. Account defaults are explicitly saved and may be reset.
- Room Settings shows the provenance: Room override / Inherited from
  account / System defaults. Explicit room reset is available only for a
  saved override. Existing unsent messages remain untouched; no navigation.
- The UI is fully localized RU/EN/HY/ES and respects the app's motion
  and reduced-motion principles.

## Non-goals / safety invariants

Neither account nor room preferences enable AI provider permissions,
auto-spend, room context access, file sharing, automatic reply, publishing
or chat Send. No history retrieved as a side effect.

## Release checklist

- Exact final SHA: Rails, Redis, Chrome, Security, Docker Compose smoke
  and production image build all PASS. Inspect tests for account/room
  isolation, invalid payloads, explicit DELETE reset, source attribution,
  and no generated/send messages.
- Owner creates **fresh** PG/media backup beyond the existing verified
  `turbo-chat-20261115T133032Z` snapshot; verify integrity. Then safe
  ff-only Git, rebuild/recreate web image as needed, single additive
  `db:migrate:up VERSION=20261115230000`, preserve changed
  `db/schema.rb`, and visually test Jack vs Eric and two rooms.
- No main merge, Railway deployment, DB volume deletion, secrets or
  uncontrolled paid provider requests.

## Next independent stages

Room Instructions V1 (text/ACL/revisions) → full consent-scoped
conversation coverage with source audit and bounded model/token budget
→ semantic context tasks and document review/Approve-Reject → media.
