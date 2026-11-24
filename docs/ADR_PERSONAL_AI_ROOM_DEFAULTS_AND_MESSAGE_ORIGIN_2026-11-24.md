# ADR — Individual AI autonomy, owner-managed room defaults and verified message origin

**Date:** 2026-11-24  
**Decision:** ACCEPTED as an owner product requirement; implementation is **incremental and incomplete**.  
**Base:** `feat/r0-live-private-group-membership-2026-11-24` at `13562c156138ff66a902833560372c100727a12a`.  
**Overrides:** earlier G3/G4/G5/D3.3 instructions requiring unanimous room-wide approval to *use* AI. This ADR does **not** waive author-content grants, room ACL, spend limits or explicit Send.

## 1. User-visible contract

- Every member (owner included) gets **the same four AI tools**: Beautify, Answer, AI Dialogue and Finalizer, subject to their actual implementation, runtime availability, individual settings and safety gates. Do not advertise unfinished modes as live.
- AI enablement, profile, writing style, language, tone, reply behavior and per-mode controls are **personal**. Another member cannot toggle, reset or veto them.
- The owner has extra **room-administration** authority: membership/invitations/removal and shared room defaults. Ordinary members can see those defaults, who last set them and their revision, but cannot edit them.
- Owner UI must distinguish **Room defaults** from **My AI settings**. Changing the owner's private choices must not secretly rewrite the shared defaults.
- Shared room defaults are inherited by members until they save an individual override. A later room-default edit affects inheriting members, **never overwrites** an existing personal override. Reset personal override means inherit current defaults.
- Each member sees others' AI ON/OFF indicator and origin badges on messages; private prompts, tokens, budget credentials and unpublished drafts remain private.
- **Remove the room-wide consent-voting/status modal and request-approval choreography.** Replace with a compact inline personal-setting indicator and a separate factual description of each author's permission to include historical text. Do not remove a safeguard just by hiding it.
- Default **no paid provider request**, **no background generation** and **no automatic Send**. Any future AI Dialogue automation requires its own budget/ACL/anti-loop/kill-switch release gate.

## 2. Separate the three capabilities previously conflated

1. **May I use an AI tool for my own output?** Personal setting and provider/runtime/budget availability. Never determined by a room unanimity count. Own unsent-draft Beautify never requires a grant of someone else's history.
2. **Whose existing room messages may be sent to an external model?** Each message author's explicit, revocable, server-held grant, scoped to a room, plus current room membership/ACL. An owner cannot grant another author's rights. No unanimous enablement switch; no implicit third-party history access.
3. **May the resulting message be posted?** Explicit final user Send, revalidated signed provenance and source authorization. Do not silently send on Generate, Preview, panel open, setting change or a WebSocket event.

A member with AI ON may use own-text generation while another member has AI OFF. For Answer/Finalizer requiring incoming context, only eligible *granted* author text can enter provider input. If that leaves no usable incoming question, show `no_authorized_incoming_context` and offer the own-draft workflow; do not substitute an unconsented message. Revocation blocks all subsequent provider use of that author's stored text, even when stale tokens or already-open panels exist.

Current `AiRoomContextConsent` represents the **author's history-sharing grant**, not permission for everyone to use AI. Rename UI labels accordingly and eventually expose truthful per-author eligibility without exposing message bodies.

## 3. Effective preference resolution

Proposed deterministic precedence, field by field:

`system safe defaults → account defaults → owner-maintained room shared defaults → member's room overrides → one-shot request overrides`.

- Shared defaults need a dedicated, audited room-owned persisted record and version; do **not** reuse `AiRoomWritingPreference` owned by the creator as hidden global policy.
- Existing `AiRoomWritingPreference(room_id,user_id)` and `AiAccountWritingPreference(user_id)` remain personal; preserve all existing rows.
- On join, show **inherited** values rather than duplicating owner settings into the invitee's row.
- For each visible value show source `room default / my override / one-shot`, effective value, editor owner and saved revision. Optimistic writes require conflict handling. Room administration remains protected by server checks independent of UI.

**Schema gate:** adding room-defaults or message-origin fields requires the existing G1 backup + isolated restore and migration approval. Never run local `db:prepare`, `db:migrate`, `db:reset`, or `db:schema:load` on the protected owner's working data.

## 4. Truthful message-origin badges

New server-verified persisted classification for **future** messages:

| Kind | UI | Source of truth |
|---|---|---|
| `manual` | Human / hand icon | Normal unassisted app composer Send |
| `ai_edited` | AI-assisted edit / pen icon | Verifiable own-draft Beautify workflow and signed proof |
| `ai_generated` | AI-generated / bot icon | Verifiable Answer/generation workflow and signed proof, followed by an explicit user Send |

The badge describes the **workflow/provenance**, not a claim that no human ever altered a sentence. Post-generation edits must not automatically relabel generated output as manual. The existing `messages.ai_assisted` boolean cannot distinguish edited from generated: preserve its historical data as `AI-assisted (legacy, subtype unknown)` until a verified migration policy is approved. Never guess a fully AI-generated subtype for old rows. Arbitrary browser form parameters cannot self-assert the origin kind. Edits, revisions and reposts must retain a verifiable audit trail or display an honest unknown state.

## 5. Required implementation sequence

- **P0 preserve/QA existing PR #20:** owner local branch `review/r0-membership-owner-2026-11-24`, protected `M db/schema.rb`, JS/CSS previously passed; successful web restart and member-count browser QA are not yet established by supplied terminal output. PR #19/#20 stay Draft; no merge/deploy.
- **P1 read-only author eligibility foundation (this branch):** `AiWorkspace::ContextAuthorPolicy` resolves current granted authors and withheld authors. It is intentionally **not wired** to the old unanimous provider flow.
- **P2 end-to-end source safety:** rewrite `RoomContextAccess`/retrieval/selection/inventory/preview/receipt/Send rechecks together so only currently eligible author messages reach AI; update membership, edits, revoke and concurrent-state tests. Merge defense-in-depth logic from separate PR #18 deliberately; do not discard it by accident. The prior unanimous-contract tests need replacement by stricter per-source leakage checks, not deletion.
- **P3 shared defaults, personal settings and room role UI:** only after schema backup gate; test multi-user inheritance/override, shared-default revision conflicts and owner-only editing.
- **P4 persisted message origin and UI:** migration gate, server signatures, backfill/legacy badge, four locales, mobile and accessible tooltip labels.
- **P5 retire room-wide consent popups:** only after P2/P3 prove truthful user-visible readiness. Keep small nonmodal inline author-grant disclosure and available/disabled states.
- **P6 R0/R1 acceptance:** exact-head full Rails + Chrome + security + Docker CI, two-browser owner test (Jack/Eric), 360/390/400px, privacy/budget/revoke/leave, no-send and recoverable backup; isolated Railway deployment **only with separate release approval**.

## 6. Explicit test matrix

- Jack AI ON / Eric AI OFF: Jack's own draft tools are not blocked; Eric remains unaffected.
- Eric history grant OFF: none of Eric's existing messages, attachments, or selected-source tokens can reach provider input; room owner's role never bypasses this.
- Eric grants only his text; Jack's ungranted historical text remains excluded. Revocation, leave/remove and changes during a request invalidate affected sources and proof.
- Shared room defaults inherited by both; Eric overrides his own language and it survives owner's later edit; Eric resets and inherits latest default; outsider cannot read either state.
- Manual, AI-edited, AI-generated and legacy AI-assisted are accurately labeled on initial render, refresh, edit, reply and message sync; forged origin rejected.
- All UI writes are user-initiated; no silent paid calls, message Send or production changes.

## 7. Status and non-goals

This ADR and the first read-only policy service are **implementation groundwork**, **not** completion of the new consent architecture, shared default persistence or three-way badges. The existing production and PR #19/#20 behaviors remain unchanged until tested follow-up slices are merged and explicitly deployed. Existing room messages, `db/schema.rb`, Railway, volumes, provider switches and paid operations are out of scope.


## 8. Saved document provenance — proposed implementation contract

**Status:** technical proposal, not implemented; requires G1 backup/isolated restore and explicit migration approval before persisted changes.

- Existing saved revisions contain cited message IDs and a document body digest, not the complete input lineage. Uncited model-derived text may still depend on a source. Do not backfill invented provenance or treat missing citations as proof of independent authorship.
- Future generated document handoff must carry a server-signed, expiring receipt bound to actor, room, task kind, generated output digest, request ID, actual complete provider input source IDs, source author IDs, immutable source-version digests, and grant revision. Room instruction revision and digest must be recorded if used. Do not store raw provider credentials or duplicate historical message bodies in the receipt.
- Persist verified lineage per immutable revision. An edited revision inherits the union of its parent dependencies and any newly verified dependencies. Removing a citation is not removal of provenance. Unverified imported text is explicitly unknown, not a verified human-only document.
- Before view, review, compare, export or update, check current owner/member ACL, every affected dependency's source existence, author identity, active grant and version. A changed or unavailable dependency blocks the affected content; a fresh authorized regeneration is a separate revision/workflow. Legacy unknown-lineage documents retain conservative legacy protection; its limitations must be disclosed rather than claimed as complete revocation tracking.
- Explicit deletion is separate: current private-room membership plus document ownership and typed DELETE; no history grant or source lookup needed. A future metadata-only management surface must make this operation reachable without loading blocked document text.
- Acceptance: mixed grants, omitted citations, forged receipt, revoked/regranted grant, deleted/edited source, departed author, historical unknown lineage, cross-room/owner denial, inherited lineage, explicit deletion without disclosure. No provider call or automatic Send from document management.


## 9. P3.1 shared-defaults persistence and API — implementation contract

**Status:** proposed branch implementation; G1 branch-only approval obtained, canonical schema replay pending. No migration added yet.

- Initial scope: private groups only, because Room#owned_by? defines an owner only there. A direct conversation has no owner; do not infer one from participant order. Personal settings remain independent in direct conversations.
- Dedicated room-owned record, proposed `AiRoomSharedWritingPreference`: unique non-null room FK, editor user FK, integer revision/optimistic lock, timestamps, profile/style/language/tone with the same existing allowlists and profile/style compatibility rules. No implicit row creation on GET or join. No grant, enablement, provider credential, budget or message text fields.
- Read: current private-group member only. Return shared snapshot, revision and last editor identity suitable for the existing member UI; never return the editor's personal settings. No-store. Missing row means no shared defaults (revision 0).
- Write: authenticated current group owner only, recheck ownership and membership under room lock, allowlisted complete snapshot and expected revision. First write expects 0, subsequent writes exact current revision; stale write returns 409 with no mutation. Serialize first insert with parent lock and unique FK index. Never silently transfer ownership or reset personal rows. Reject forged room/user/editor/revision or enablement keys in settings payload.
- Inheritance: preserve existing complete personal room snapshots as explicit overrides, including legacy nil profile semantics. Shared complete writing snapshot applies when no personal room row exists; otherwise existing personal snapshot wins. Without shared row, retain account/system behavior. This is initial full-snapshot compatibility, not yet the target per-field override UX; do not silently migrate existing rows into partial overrides. A future partial-override representation must treat profile/style as a coupled pair and distinguish absent/inherit from explicit value. Reset personal row inherits latest shared/account/system; no copied owner settings on join.
- Personal AI ON/OFF is separate persistence and independent runtime control; shared record must never control another member's enabled state. Default for existing users and rollout compatibility must be decided before runtime wiring. No provider calls or automatic Send in settings actions.
- Acceptance: owner first create and revision increment, member read/nonowner write denial, outsider read/write denial, departed owner/member denial, stale revision 409, invalid profile/style and unknown fields 422, no shared row on GET, independent owner personal override, member override survives shared edit, reset inherits current shared revision, no cross-room writes, no change to existing account/room preference rows or author grants. Test fresh migration replay plus additive upgrade preserving representative prior rows on disposable PostgreSQL; rollback test only disposable DB.
- Rollout order: canonical schema commit from verified replay first; additive migration + model; isolated migration/constraint tests; owner/member service/API; resolver and personal enablement; UI with truthful origins. Do not enable incomplete UI or weaken legacy document protection.
