# ADR — Conversation-first AI Experience V1 (2026-11-15)

Status: **product contract + offline, code-owned preference resolver only**. No
automatic provider requests, no migration, no live room-setting persistence, no
new user-facing controls, no changes to Send or translated messages in this slice.

## Product decision — conversation is the product, AI is an invisible assistant

The owner accepts the previous inline-source and policy UX but rejects a
workflow that requires opening a large AI panel for normal chat use.
Primary interaction: type → optional one-tap Beautify shows **my version /
AI version** side by side → select the version → Send. Avoid changing or
sending the person's original text unless a previously reviewed policy
explicitly authorizes that behavior. No silent paid retries, "AI thinks" false
indicators, or invisible publication.

For conversation deliverables: existing room-authorized excerpt selection →
suggest the next useful output → explicit Generate → preview/revise →
explicit Save → separate approval/export/Send. User can always change a
recommendation and see which sources were used.

## Preference scopes (strongest wins)

1. **Message**: one-shot tone, language, writing style, Beautify and output
   selection. Never changes room defaults.
2. **Dialogue / active task**: goal, output type, working tone; may inherit room
   settings, but does not grant permission to browse a new room.
3. **Room**: available at room creation, reusable config profile, languages,
   voice, and allowed assistant behavior.
4. **Account**: personal defaults across the user's rooms.
5. **System**: neutral general-purpose fallback.

Security policy (membership, current all-member consent for shared history,
provider disclosure, budget, data retention, human-controlled Send) is
**not an overridable scope**. A reusable configuration is NOT consent.

Profiles at V1 contract: universal, business, personal, dating, development.
They map to existing writing styles/task names but add **no arbitrary raw
system prompts** or account-level trust. The resolver validates an allowlist
of fields and values and records the origin of each effective setting. Existing
six writing presets and three agency deliverable presets are retained.

## Automatic assistance: desired behavior vs actual availability

- Native spellcheck and offline/on-device translation are low-risk defaults.
  Incoming translation should offer "on if supported" without a panel; the
  original must remain available. **Current application still starts incoming
  translation opt-in**; Chrome translation availability, permission/model
  download, source detection and language-pair support vary. HY is in the UI
  list but not in the local Chrome translation allowlist. Do not promise HY
  translation before an eligible, privacy-reviewed solution exists.
- Beautify is discoverable next to the composer. Preview is reversible;
  Apply never Send. A model result must be marked, compared and stale-draft
  protected. Current own-draft xAI calls require an explicit manual request.
- Automatic paid Beautify on Send is a **separate future gate**: explicit
  per-user/room authorization with a capped budget and safe failure behavior,
  no implicit consent inferred from choosing a profile, and a deterministic
  policy for which text is sent to the peer if AI is unavailable. Until that
  release gate, normal Send continues to send the typed/accepted draft.
- Shared room-history assistance requires current explicit consent from
  every participant, current access checks and bounded reviewed sources.
  Personal draft handling does not inherit those rights.

## Implementation sequence / acceptance criteria

1. **V1 resolver** (this commit): pure `ConversationExperienceV1.resolve`.
   Validates profiles and precedence; computes truthful feature availability
   from passed runtime capabilities; hard safety remains non-overridable.
   No API endpoint/storage/side effects. Unit tests deny unsafe overrides.
2. **Basic room configuration**: one-click profile and three high-value
   controls (assistance, language, tone), with an advanced drawer; bind real
   room/account preferences after approved additive schema/backup migration.
   Make creation → preset → chat a one-screen journey.
3. **One-message experience**: one-tap Beautify preview (original vs AI,
   clear pending/error/charged status); optional apply, quick undo, then Send.
   Do not send any provider request on each keystroke. If automated processing
   is authorized later, enforce budget, stale-result and cancellation gates.
4. **Incoming translate**: opt-out on-device/default if truly supported.
   Preserve original and clearly show unavailable pairs, including HY.
5. **Conversation/Deliverable mode**: detect useful output from consent-scoped
   history, hide complexity by default, reuse existing H4/H5 document/version
   lifecycle, distinguish Save, Approval and Export.
6. **Reusable profiles across devices** and longitudinal QA; measure useful
   accepted outputs, manual corrections, latency, cost per accepted output,
   and lost-draft incidents rather than button counts.

No `db/schema.rb` reset, no secret storage, no main merge, no Railway deploy.
