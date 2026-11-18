# ADR — Gate 2B.6: AI consent, context, provider and budget readiness (2026-11-09)

**Status:** proposed offline security/UX contract; **not** approval to run AI. Applied to the existing Draft PR #2 on `feat/security-baseline-2026-11-03`. No live inference, payment, database migration, stored consent, AI output, or network gateway exists in this gate.

## 1. Decision and existing implementation

Relay Workspace will start real inference, if separately approved, with **manual, own-draft, on-demand** operations only. The current room composer remains the author-controlled editor: open the one sparkles entry, inspect a suggestion, Apply/Undo, then independently Send. Preferred preset and browser spellcheck stored in localStorage are **not consent**. `AI OFF` and `AUTO OFF` remain true until actual server-authoritative prerequisites exist.

Already implemented (do not duplicate): `AiWorkspace::Scope` limits explicit room-local text selection to 1–8 message IDs / 750 characters per selected message and checks membership; `ContextPolicy` accepts manual only; `ContentPipeline` prepares own drafts or selected messages locally, refuses approved context; immutable six bundled presets; bounded preprocessor; `Gateway.configured? == false` and `generate!` raises. Current room AI page is an offline review, not an outbound endpoint. The code-level 5,000 Unicode character / 20 KB draft limit is **not** a token or monetary budget.

**New policy decision:** there must be one server-enforced, auditably versioned authorization gate at both request admission and immediately before any outbound model invocation. UI and localStorage are only representations of server state. No new Rails endpoint or actual provider integration is authorized by this ADR.

## 2. Scope and participant authorization matrix

| Source / room | Current local preparation | Proposed outbound prerequisites | Default now |
| --- | --- | --- | --- |
| Own draft, any accessible room | Actor + active membership, `source_ids=[]`, bounded text | Verified actor and room membership; explicit per-request consent to a disclosed provider and data categories; budget reservation; only own draft text | Provider DENY |
| Selected messages authored by actor | Explicit authorized selection, existing Scope bounds | Above, plus snapshot of source IDs + provenance; per-source policy check | Provider DENY |
| Selected **other participant** messages in DM | Explicit local selection may be previewed | Approved transparent DM policy and applicable participant permission/consent; revalidate at send; do not infer permission from visibility alone | Provider DENY |
| Private group history | Explicit room membership and selected IDs locally | Room governance, policy version and required affected-member consent; join/leave/removal/revocation checks | Provider DENY |
| Public room history | Must be a current member even to preview | Public *inside the app* is not automatically shareable with external LLM; room governance and required rights | Provider DENY |
| Smart/automatic room context | Not implemented; `ConsentRequired` | Explicit room-level opt-in, source preview, bounds, revocation and approved member policy | DENY |
| Agent context, connected Gmail/Drive, cross-room data | Not implemented | Independent connector scopes, purpose, audit and per-action approval; never assume OAuth access implies LLM permission | DENY |
| Attachments/media, OCR, voice and video | Not part of current text-only context | Independent selection and rights, MIME/size/security/price checks, fresh blob ACL at dispatch | DENY |

The existing `accessible_to?`/membership guards remain authoritative for *local previews*; they do not grant permission to transmit other people's text externally. A new joiner does not retroactively approve prior history; a former member cannot use cached source IDs or saved links. Do not generalize any one consent rule into a legal conclusion without launch-jurisdiction/provider review.

## 3. Proposed server-side state and transitions (not existing tables)

**Room policy:** `disabled -> manual_candidate -> enabled_manual`; `enabled_manual -> paused | revoked | disabled`. Default disabled. A new policy version, changed provider, changed data category, ownership transfer, group membership change or affected participant revocation invalidates outstanding approvals as defined by the reviewed policy. Smart/agent remain separate policies and never inherit manual approval.

**Participant consent:** actor/scope/source category, policy version, informed provider disclosure, grant time, expiration, revoke time, permitted purpose, auditable immutable transitions. No consent embedded in a browser setting or inferred from read access. Revoke must immediately block admission and dispatch; revocation cannot recall data already sent to a provider, and this limitation must be disclosed.

**Request lifecycle:** `rejected` or `queued -> running -> completed | failed | canceled`. Only `completed` may expose a validated suggestion to its authorized author. Do not expose user/model text to unrelated members; cancellation is best-effort after outbound transmission. Retry uses a stable idempotency key and may require a new budget reservation if it is actually a new inference. Recheck draft revision against the source before Apply; stale proposals never overwrite newer typing. Sending remains a separate manual action.

**AUTO:** `OFF` by default. Future auto-suggest requires separate explicit opt-in, throttle/debounce, bounded server quota and live consent/provider/room policy. It cannot silently send/publish, process every keypress, inherit selected-history permission, or stay ON after revoked consent/kill switch/budget exhaustion.

## 4. Single outbound admission gate (future implementation contract)

1. Authenticate server actor; bind room and selected message IDs from server-authorized records; validate operation, immutable preset version, locale and bounded payload.
2. Determine `own_draft | selected_history | smart_history | attachments`; reject all unknown sources and client-supplied instructions/consent overrides. Default scope is manual own draft.
3. Check live room membership and exact source rights; verify applicable room policy version, participant consent and data purpose. Use a server-side policy evaluator, not toggles/client claims.
4. Verify configured, approved provider/model allowlist, allowed deployment region and actual data processing/retention disclosure. Check explicit per-request requester's approval.
5. Atomically reserve worst-case usage under user, room/workspace and monthly caps before dispatch; reject if any hard cap cannot be guaranteed.
6. **Immediately before outbound:** repeat actor/room/source/consent/revocation/policy version checks; match prepared source snapshot and request's scope/expiry. Deny on any ambiguity or late permission change.
7. Dispatch bounded request with timeout, idempotency and circuit breaker. Treat model instructions embedded in messages as untrusted content; no system-prompt override.
8. Validate result length/format, escape output safely, attribute sources, settle measured cost, release unused reservation; failure/cancel/unknown price follows conservative accounting and visible error. Never auto-send or silently persist drafts.

Before a real implementation, decide how to make the final permission check and reservation safe against concurrent revocation/dispatch (transaction/lease or equivalent). A controller-level check alone is insufficient. A fully atomic guarantee cannot be asserted for an external provider after its HTTP request has started.

## 5. Provider selection and privacy approval checklist

**Needs owner approval and fresh official evidence:** provider legal availability for the operating entity and location; permitted API use; model and model version; rates, input/output limits, currency, rate limits; data processing/training/retention, region, subprocessors, deletion and contractual constraints; lawful payment method and invoicing; emergency kill switch. Do not assume any existing ChatGPT/Gmail/Drive connection is an application backend provider.

API credentials only in server secret management. No credentials in Git, Drive, browser, localStorage, URLs or logs. No prompt, generated private text, personal identifiers, email addresses or client attachments in logs by default. Metadata audit should record actor/room IDs, operation, approved source-ID hashes, policy/preset versions, provider/model identifiers, timestamps, state, measured tokens and costs without leaking content. Adopt documented retention/erasure and accessibility rules **before** storing model inputs/outputs.

## 6. Budget and idempotency — planned, not active

Define server-authoritative hard caps for maximum spend **per request**, **per user/workspace per day and month**, input and output token caps, plus a global kill switch. Currency normalization is permitted only after verifying actual model price and payment currency; no invented USD/AMD exchange rates or cost figures.

Use atomic `reserve -> running -> settle measured actual -> release difference`, under concurrency-safe uniqueness on `actor + idempotency key + policy version`. Reserve upper-bound estimated cost, including maximum output tokens. Retries reuse the same request only when safe; rejected requests do not spend. After network uncertainty, reconcile provider billing before releasing disputed reservations; never promise that cancellation means zero cost. Show a user-visible estimate and maximum before opt-in, then measured amount after success. Quota bypass by parallel requests, different rooms, client parameters or retries is an acceptance blocker.

## 7. Suggested minimal domain model and migration gate

**PROPOSAL ONLY:** `AiRoomPolicy` (version, mode, responsible actor, revoked/paused state), `AiParticipantConsent` (scopes, covered policy version, expiry/revocation, immutable audit), `AiRequest` (server-authorized actor/room, provenance hashes, preset snapshot version, state, idempotency), `AiUsageEvent` (reserved and measured cost/tokens, authoritative accounting), and only later `AiArtifact` (output, visibility, author approval, revisions, retention). Provider configuration should use server-side allowlist and secret store rather than storing API keys in model rows. Avoid creating `AiPreset` yet: bundled registry already exists.

No schema change in Gate 2B.6. Before any additive migration: inspect user's intentionally modified `db/schema.rb`, compare migration status and current DB shape, record backups and successful restore/rollback route, obtain **separate owner approval** for each concrete DDL change. Do not reset, reload, delete volumes or mutate local Jack/Eric data.

## 8. UX truth contract

Existing sparkles / Edit draft / Room settings remains the single composer entry. Keep `AI OFF` and `AUTO OFF` while this gate is offline. Future consent UI must show provider, purpose, exactly which selected sources will leave the service, potential retention, maximum spend, cancel/decline path, revocation path and a separate explicit Run confirmation. For historical context, show a preview of selected message IDs/authors and affected scope. No consent obtained through a pre-checked checkbox. Disabled controls explain what prerequisite is missing; stale result, quota denial, timeout, permission revocation and offline state have distinct messages. Results require Copy/Apply/Discard and explicit separate Send.

## 9. Negative-test and release-acceptance matrix

- Deny guest/nonmember/former member after Leave/Remove, before/after selected preview, and at provider dispatch; no stale room access, streaming, blob or output leak.
- Deny forged actor/room/source IDs, cross-room selections, duplicates, oversized input, unknown preset/operation, unauthorized history, smart/agent and attachment modes.
- Deny absent/expired/mismatched policy version, missing affected-member consent, participant revoke, owner transfer and group membership change; ensure public room is not automatically provider-public.
- Deny missing provider/model approval, disabled gateway, expired request, kill switch, insufficient or raced budget, concurrent duplicate idempotency, late revoke and retry after permission loss.
- Verify no auto-send or draft loss, no raw logs, no arbitrary HTML from the model, error-only failures, and no provider call before consent/cost controls are operative.
- Verify genuine own-draft provider result with actual metering only after later explicit approval and an agreed safe dummy-text local acceptance.

**Verification in this gate:** commit ADR and narrow, negative offline regression tests of existing authorization/gateway boundaries. Exact-head Rails/PostgreSQL, Redis/Cable, Chrome, Security and Docker workflows must be green; three inherited Rails skips remain an explicit issue. No user-local UI acceptance is needed for a documentation/test-only slice.

## 10. Next decisions / explicit non-goals

Next independent H2.1 slice: adjust existing Signal Deck Writing Tools popover geometry and contrast, then owner screenshots at desktop 1440 and mobile 390. Separately, choose provider, billing caps, consent/retention policy, minimal migration and disaster-recovery plan **before** H3 real own-draft AI.

This ADR is design intent and safety requirements, **not** working consent/billing/provider infrastructure, not a security audit certificate, and not authorization for Railway/main merge/public release.