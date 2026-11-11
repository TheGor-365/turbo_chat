# H4 Automation-first document workflow — initial offline slice

Date: 2026-11-12. Draft PR #2, branch `feat/security-baseline-2026-11-03`.

## Product decision

**Default is automatic. Manual intervention is available when needed.** A user should not need to paste Markdown, manually construct a document or compare two raw Markdown versions to get value from a conversation. The destination workflow is:

`Authorized conversation → automatic draft → evidence/status inspection → optional edit and diff → separate human approval → optional separate Send/export`.

Auto-draft must never mean automatic external billing, AI consent, approval or sending. H4 remains ephemeral. H5 persistence and audit trail require separate owner approval.

## This slice

- On a consent-authorized GET to `/rooms/:id/ai/deliverable-review`, `RoomAiDeliverableReviewsController#new` automatically constructs a local **extractive evidence digest**, using `ReplyContextBuilder` (bounded source text, DLP/room membership checks, all current participants' consent).
- `AutomaticEvidenceDraftV1` quotes up to six available messages with explicit `[M<id>]` references. It strips embedded citation brackets from untrusted excerpts, makes no semantic claim about agreements, and labels uncited open questions **needs_confirmation**. Cited extracts are **inferred** until a person reviews them.
- The draft is immediately shown in the existing typed H4 review controls, with direct authorized source links. Proposed-version editor is prepopulated from the same draft. No copy/paste or initial Inspect click required.
- Inability to build a safe draft returns a neutral, empty manual fallback, not an external model request. The `?demo=1` synthetic fixture still exists for no-cost testing.
- Neither opening the page nor revising/reviewing a document stores a document, writes a chat message, calls xAI, spends credits, approves a requirement or changes permissions.

## Scope of automation

This is **not yet** an AI-authored client brief. It is a traceable, explicitly labeled extractive working document. Transforming excerpts into a meaningful brief/proposal requires the controlled provider path, participant consent, documented retention and budget limits, and manual gate for approval. Model-generated conclusions must stay inferred/unknown until checked.

## Acceptance and release gates

- Confirm exact-SHA Rails tests, security audit and Docker smoke; previous `8982e04` Rails CI had a provider-flag-dependent H4 navigation assertion failure plus Redis integration issues. Test was made feature-flag independent.
- Confirm in browser: room toolbar `check-check` → H4 automatically shows entries from eligible incoming text and source links without clicking Generate, paying or pasting. `?demo=1` continues working.
- Verify revocation, cross-room forged citations, no eligible incoming source, rendered HTML escaping, 36-item/5,000-character bounds and no message writes.
- H7 Redis realtime test stability is a separate existing gate.
- H5 persistent version history/approval/rollback/database migrations remains **not approved**, and neither schema nor Railway are touched.
