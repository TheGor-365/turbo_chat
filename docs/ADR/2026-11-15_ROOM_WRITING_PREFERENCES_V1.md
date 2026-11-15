# ADR — Room writing preferences, first server-bound slice (2026-11-15)

Status: draft PR #2; server schema migration and browser acceptance pending local approval.

## Scope and data ownership

- `AiRoomWritingPreference` is **per account in one accessible room**, not shared across other members.
- Data: optional profile ID, allowlisted writing style, preferred language, preferred tone. No message bodies, raw prompts, attached files, passwords, provider tokens, paid consent or privacy history.
- One unique composite index `user_id + room_id`. Deletes follow room/user deletion. A room member cannot save for a different user, another room, or after removal.
- New additive migration `20261115152000_create_ai_room_writing_preferences.rb`; no `db/schema.rb` edits in PR. **Never run db:reset, db:schema:load or volume deletion.**

## API and client behavior

- `GET /rooms/:room_id/ai/writing-preference` and `PATCH` require authentication and current room membership. JSON responses are private/no-store; PATCH accepts a complete allowlisted snapshot only.
- Existing Room Settings profile/style changes persist to the server in a serialized request queue. Native spellcheck remains device-local. Server-saved state takes precedence over old browser-local preferences on the next page load. When offline or PATCH fails, the original chat and local fallback remain functional and report failure to sync.
- Locale/UI: RU, EN, HY, ES, compact language and tone dropdowns. These **preferences do not automatically translate, call the provider, change other members' settings or authorize spending**.
- A persisted **writing_style** is consumed by the existing `ai-draft` controller: pressing Beautify uses this selected preset for the already-existing manually authorized xAI endpoint. `language` and `tone` are stored as preferences only in this first slice; no unreviewed extension of paid prompts or inference is claimed.
- The previous `ConversationExperienceV1` allowlisted resolver remains the rules source. The model invokes it to get effective settings; safety invariants are unchanged.

## QA and release gate

- Rails controller tests: guest/outsider/revoked member denied; user and room isolation; unknown/forged values rejected; no automatic Send or provider spending.
- Chrome tests: selection and confirmed server write, no localStorage dependency on reload, custom language/tone persisted, zero messages sent.
- Full exact-SHA Rails, two-browser Chrome, Redis, security, Docker/Compose smoke and isolated production build must PASS before owner update.
- Before local rollout, back up actual PostgreSQL and locally changed `db/schema.rb`, confirm restore readiness. Only then apply new additive `db:migrate` to the existing volume and rebuild/restart web.
- `main`, Railway, existing production volumes, KYC data and external provider keys remain untouched.

## Next independent slices

1. Account-wide profile defaults and narrow scope precedence with room overrides (separate controlled migration and explicit UI).
2. Versioned H5 deliverable member approvals after consent+ACL review; H5 export to .md/.txt already exists.
3. User-accepted desktop/mobile screenshots, then production readiness, backup/PITR, separate Railway demo and portfolio packaging.


## Burst-safe preferences

The authenticated settings endpoint has a dedicated 60 updates/minute throttle
per user/IP, separate from paid generation throttles, which remain unchanged.
This bound accommodates quick profile/language/tone changes and parallel
browser acceptance suites without accidentally rejecting safe settings.
Server rejects are surfaced as a localized browser-only fallback with HTTP
status for diagnostics. A failure does not erase the current composer draft.
