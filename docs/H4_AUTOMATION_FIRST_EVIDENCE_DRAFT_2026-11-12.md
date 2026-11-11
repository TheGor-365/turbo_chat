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

## Follow-up: automatic Client Brief (2026-11-12)

- At SHA 697cbf0, an earlier generated **Client Brief** appeared as citation [M32] in an automatic digest. Rails CI confirmed the faulty filter; Ruby regex escaping and its word boundary were corrected.
- Default H4 GET now uses AutomaticClientBriefV1 to produce a citation-first, extractive Client Brief from filtered authorized room messages.
- Sections are Objective, Requirements, Constraints, Deliverables, Acceptance Criteria, Open Questions. Attributed statements are labeled reported, not agreed; unknown budget, scope and delivery specifics remain To confirm.
- This is not semantic agreement detection or a paid AI-authored specification. Manual approval and Send remain separate. H5 version persistence still requires backup/migration approval.
- Outstanding: model-backed semantic extraction with explicit budget and opt-in, validated citations, injection tests, browser acceptance and H7 realtime stability.

## H4 semantic-provider output gate (2026-11-12)

- Added `SemanticDeliverableGateV1`, a pure offline post-generation structural inspection for Client Brief, Client Proposal and Conversation Summary. It parses strictly authorized `[M...]` citations through the existing typed contract, checks mandatory sections and returns human-review warnings for potentially unsupported agreement language.
- `ContextTaskGeneration` now attaches advisory `structured_review` metadata after its existing output and evidence checks. Model text remains ephemeral and never approved, persisted or sent to a room. Invalid formatting yields an explicit incomplete/unavailable status rather than a fake approved document.
- Keep accounting sound: since a provider response might already be billable, a structural format failure does not skip `LocalBudgetLedger#settle!`. Existing explicit one-request confirmation and room-wide consent remain mandatory. No paid call or feature flag was activated during implementation; test uses a fake provider.
- Remaining gates for end-user semantic AI: owner approval for actual provider usage/budget, review UI for structural warnings, live ACL after generation, stricter semantic contradiction handling, consent-revocation tests under concurrent generation, and controlled browser acceptance. These checks do not prove the model's factual correctness.

## H4 controlled semantic-result readiness (2026-11-12)

- Existing contextual generation is an explicit one-request paid action behind feature flags, unanimous live room consent, per-request confirmation, current source selection and local budget reservation/settlement. No background/automatic billable invocation is allowed.
- After the model response, the typed structural gate produces `structured_review` metadata (`complete`, warnings, review state). The JSON route exposes it and the existing `Formatted Preview` now shows either ready for manual review or incomplete/needs review, using Signal Deck styling. This does **not** assert factual correctness, make a document approved, or invoke Apply/Send.
- The existing Review icon transfers a compatible draft through a fresh room ACL and citation-validated POST into H4. Unsupported output is rejected, leaving the working copy intact. No migration or new storage was added.
- The default H4 remains local, extractive and no-cost. No xAI flag, key, payment or Railway deploy was changed. A paid semantic Client Brief must be explicitly initiated by the room member after all consent/budget gates are configured and approved.
- Acceptance still requires a controlled browser run with a stubbed provider, proper budget/consent regression tests, and resolution of the independent H7 Redis system-test instability. This is not a claim of production-ready semantic AI.

## H4 mock-model browser acceptance (2026-11-12)

- Added request-level acceptance covering the existing context-task JSON contract with a fake model response (`structured_review`, room-local source links and reported zero cost), followed by an actual POST into typed H4 Review. It checks six entries, cited and unconfirmed statuses, no writes, and immediate denial after room-wide consent revocation.
- Added Selenium browser acceptance for the Signal Deck H4 page: load synthetic source, paste mock structured Client Brief, click the real Inspect control, verify statuses, source links, revision editor and no chat message. No xAI key, live model call or payment is used.
- These tests are complementary: the request test exercises the stubbed provider-to-review boundary; the browser test exercises destination rendering. A complete live browser click through actual generation, cost confirmation and H4 handoff is **not** claimed until explicitly approved provider testing or a test-only harness with equivalent browser state is implemented.
- Keep external generation explicitly opt-in; do not start requests in response to page load, and do not conflate structural completeness with factual correctness or participant approval.

## Single-use paid Client Brief consent and Workspace discovery (2026-11-12)

- AI Workspace explicitly separates free **Automatic Client Brief** (local extractive source-backed review) from optional **Semantic AI** (model-supported, billable, never launched by visiting the Workspace). Its status reflects whether development-only generation flags and provider key are enabled; no permission or billing is granted by opening the page.
- The conversation's contextual-task UI requires the actor to actively check a single-use authorization before Generate is enabled for `client_brief`. It explains that the local budget ledger reserves $0.10 per request and actual provider charges can differ. Confirmation resets immediately before the request starts, including failed and rejected requests; it does not persist across tasks, opens or reloads.
- Existing backend room-wide grants, fresh ACL, budget reservation, source selection and explicit `consent: '1'` remain authoritative. The checkbox is additional UX friction, not a substitute for server controls. No automatic xAI call, Apply, Send or approval is introduced.
- Test coverage includes browser disabled-before-consent/one-use-after-attempt and controller discovery of the correct free and paid pathways. Do not enable provider flags or distribute API secrets to test the offline flow.

- Navigation acceptance: AI Workspace shows active **Semantic Client Brief** only when development provider flags are enabled. Its link to `/rooms/:id?ai_task=client_brief` opens the existing conversation editor with that task selected; it never calls Grok. When disabled, the Workspace displays a non-clickable explanation. The link is tested with controlled feature flags in a browser.
