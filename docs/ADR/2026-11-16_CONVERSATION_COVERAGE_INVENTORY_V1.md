# ADR — Full Conversation Coverage, phase 1: offline inventory (2026-11-16)

Status: **implementation candidate in Draft PR #2; exact SHA CI and owner acceptance required**.

## Scope and trust boundaries

The existing contextual AI pipeline still scans at most 240 recent candidate messages and sends at most 9 excerpts / 2,400 characters. Its `omitted` count is not a full-history count. This new service is a standalone, **server-only, read-only inventory**. It does not change the paid provider pipeline, preview UI, source token, database schema, or budget ledger.

- Requires `AiWorkspace::RoomContextAccess`: eligible private room, current membership and unanimous active consent before any history scan and again after it.
- Inspects text bodies only for CURRENT authors. Counts but never loads departed authors' message bodies, other rooms or attachments.
- Uses ID watermark and batches of 200; default maximum 10,000 message rows. Above the bound, fails closed rather than claiming to have scanned the whole room.
- Counts total rows, current-author scanned rows, safe text, former-author excluded, non-text, sensitive warnings and invalid text. Emits **no raw message body, message IDs or warnings containing secrets**; only an internal SHA-256 fingerprint over the enumerated current-author sources.
- Confirms unchanged roster, current consent, watermark and row count at the end. Inserts, deletes or permission revocation during a scan fail closed when detected.

## Important limitations

The multi-query fingerprint is NOT an atomic repeatable-read snapshot: concurrent edits can produce mixed versions. This report is not a signed review, provider authorization, stable evidence ledger or proof that the AI saw the entire conversation. **Never** serialize it into a paid provider request or turn it into user-facing evidence without a separate approved gate. No new API endpoint is exposed. No migration, external provider call, chat Send, Railway deploy or file processing is part of this slice.

## Next release gates

1. Transactionally consistent snapshot / versioned source IDs and current-author consent, with revocation and edit/delete invalidation, under large-history and concurrency tests.
2. Authorized, paginated coverage preview displaying honest `total / eligible / excluded / included` categories and reasons; no untrusted raw text in logs.
3. Versioned retrieval and hierarchical summaries, budget/token/TPM estimation and signed user review before any broadening from 9 excerpts. No automatic provider spend or Send.

Owner Linux handoff: this is server-only; do not run a migration or reset any DB/volume. Preserve local modified `db/schema.rb`; wait for 4/4 CI on the exact new SHA before updating local code.


## FCC-2a read-only snapshot candidate (2026-11-16)

Added `AiWorkspace::ConversationCoverageSnapshotV2` as an independent internal
service. It **does not modify V1, ReplyContextBuilder, provider payloads,
stored messages, consent state or cost controls**. Existing 240-message candidate
window, nine excerpts and 2,400-character provider budget remain unchanged.

The V2 service:

1. Requires private-room access and unanimous current member consent.
2. Captures eligible membership and grant timestamps, then reads up to 10,000
   room rows in **one ordered PostgreSQL SELECT**. PostgreSQL MVCC makes that
   single statement internally consistent. SQL CASE returns NULL instead of
   the body for departed authors; file attachments are not queried.
3. Emits counts for total, current-author and eligible safe text, with separate
   departed-author, blank/non-text, sensitive and invalid buckets.
4. Returns **only metadata** for eligible safe text: message ID, author ID,
   updated timestamp, SHA-256 of body and per-source version fingerprint.
   It does not return text, attachments or messages of departed users.
5. Re-reads the bounded rows in a second statement and compares a digest
   over all authorized source content. This catches observed edits **even if
   updated_at was not changed**, deletions and inserts.
6. Re-checks membership and consent timestamps at each boundary. Detected
   roster change, consent churn or source change invalidates the report.

**Non-guarantees:** Two SQL statements are not an atomic repeatable-read
transaction. Changes after final validation can still make the report stale;
an edit entirely reversed between checks may be missed. A fingerprint is not
a signed approval or authorization for a future provider request. Eventual
retrieval, preview or dispatch must validate membership, unanimous consent,
cost and every selected source again before using any content.

**Next gates:** authorized coverage preview with honest denominators and
omission reasons, version-checked retrieval with immutable source references,
then hierarchical semantic synthesis with citations, conflict/uncertainty
markers, explicit spend estimate and user review. Do not send full room
history to an LLM or infer agreed terms from provisional discussion.


## FCC-2b: explicit coverage API candidate (2026-11-17)

The private JSON GET endpoint `/rooms/:room_id/ai/coverage-preview` uses
`ConversationCoverageSnapshotV2`, without contacting xAI, reserving budget,
creating messages, changing grants or selecting provider sources. It is
available only to authenticated current members of eligible private rooms
after every current member has granted room-context consent.

- No request parameters are needed for the first page; optional `page_size`
  is 1–50 (default 25). The source page contains only eligible safe-text
  message IDs and update timestamps, **never bodies, hashes, attachments,
  email, name, or former-author message IDs**.
- Exact counts cover all message rows within the 10,000-row cap:
  total, current-author, safe-text eligible, and excluded grouped by
  `former_author / non_text / sensitive / invalid`. In this endpoint
  `eligible` means inventoried, **not included in any provider request**.
- If more pages are available, a signed five-minute `next_page_token`
  binds the room, viewer, consent signature, page size and content fingerprint.
  Every page recomputes and verifies the current inventory; edited messages,
  changed grants and altered page size invalidate the receipt. A client must
  restart with page 1 after expiry.
- Returns `private, no-store` / `nosniff`, rate-limited to eight requests
  per minute, and a generic error for invalid/expired access or pagination.
  Unknown or public rooms and nonmembers are denied.
- This API is **not yet linked to the visible AI panel**. It does not certify
  factual correctness, allow sending a full chat to Grok, or broaden the
  existing nine-excerpt/2,400-character AI budget.
- The underlying V2 read remains two distinct SQL statements, not a durable
  transactionally locked version. A successful page receipt cannot authorize
  later provider dispatch. Later work must validate consent and source
  versions at selection and dispatch boundaries.

Next: test the endpoint and rate limit in CI, then an accessible user-facing
coverage overview with honest missing-data warnings, followed by evidence
retrieval and semantic classification of proposals vs confirmed decisions,
including explicit uncertainty and contradictory source references.


## FCC-2c: user-triggered coverage panel (2026-11-17)

The existing "Context sources" action in the AI draft editor now contains a
separate, nested "History coverage" disclosure. Opening either disclosure
makes **no network request**. Only clicking "Check history" calls the
consent-checked FCC-2b endpoint, without a model/provider request or budget
reservation. The data is not stored in localStorage or server-side by the UI.

The panel presents the total message count, eligible safe-text source count,
exclusion count and breakdown by reason. It links only eligible source IDs
back to the authorized room message, never displaying bodies, author
identities, content digests or model claims. Further pages require explicit
"Next page" clicks using the five-minute signed receipt. Closing the coverage
disclosure aborts outstanding requests and erases rendered counts/links.
Invalid, expired or revoked requests clear the view with a generic error.

New Stimulus controller `ai_coverage_controller.js` is isolated from
`ai_draft_controller.js`: coverage cannot set the signed provider selection
token, choose sources for xAI, mutate an unsent composer draft, send a message
or enable consent. The existing provider context preview remains limited to
nine excerpts / 2,400 characters, independent of coverage.

The counts mean **inventoried**; they do not imply semantic understanding,
factual confirmation, complete coverage beyond the 10,000-row cap, or
permission for a later provider dispatch. Closed UI is not a security
boundary; every server request must reauthorize. Planned next gate:
version-checked evidence retrieval, provenance and explicit
proposed/confirmed/revoked/contradictory classification with human review.


## FCC-2c.1: on-demand message preview and style-picker parity (2026-11-17)

The coverage panel's eligible ID list now uses text-only buttons with no
underlines. Clicking a specific ID (never merely opening the panel) requests
`GET /rooms/:room_id/ai/coverage-preview/messages/:message_id`. Its result
appears in a dedicated native modal dialog with a close control and Escape;
the room page is not navigated and the unsent draft is not changed.

Security boundary: the ID is **not** an authorization token. Each request
checks logged-in private-room membership, unanimous current context consent
and bounded source eligibility, then loads only the selected message's body,
checks DLP on its entire text and verifies its content fingerprint (including
edits that bypass `updated_at`). It performs a second consent-scoped snapshot
after reading the body to detect concurrent membership, consent or message
changes. Former-author, sensitive, blank and out-of-room messages cannot be
previewed. Each request is read-only, `no-store`, rate-limited, and never
invokes xAI or reserves budget. There is still no global lock across all DB
operations: mutations *after* final revalidation can change the room.

The client creates the modal on explicit user action and displays the text
using `textContent` (no Markdown/HTML rendering). Closing, navigating or
disconnecting aborts the request and removes content from the DOM. Lists
remain metadata-only and the message text is not persisted as a cache.

The draft style disclosure now reuses the room style-picker classes and
full-width summary layout, with one visible chevron and the existing
preset and preference persistence behavior. No migrations or provider
contracts change. Browser and controller tests cover permissions, DLP,
changes, modal interaction and style parity.

**Next gate:** semantic evidence retrieval and explicit classification of
proposed / confirmed / revoked / conflicting statements. Avoid treating the
mere existence of a source message as proof of approval.


## FCC-2d: offline evidence candidates with explicit human review (2026-11-17)

A separate **manual POST** endpoint
`/rooms/:room_id/ai/evidence-search` accepts `evidence_query` (3–120
characters; secret/email warning strings rejected). It does not call xAI,
select provider fragments, enable consent, reserve budget, create messages,
or modify the existing nine-excerpt / 2,400-character Grok contract.
`evidence_query` is filtered from Rails parameter logs.

Request security:
- Only authenticated current members of eligible private rooms with unanimous
  active context consent. Rate limited to six searches per minute.
- A fresh FCC-2a snapshot (up to 10,000 messages) identifies safe current-author
  source IDs. SQL conditions are parameterized and constrained to these IDs
  before fetching text. Former-author, out-of-room and DLP-flagged text is
  never included in query results.
- Matching source bodies are checked against the first snapshot's body SHA
  and update timestamp. A second whole-room snapshot must match source and
  consent signatures before any result is returned. This detects observed
  concurrent edits/revocations, including edits made without touching
  `updated_at`. No guarantee against changes after final validation.
- At most 400 **latest matching candidates** are scored and 12 excerpts
  (each at most 240 characters plus ellipses) are displayed. If 400 is
  exceeded the response explicitly flags that older matches may be missing.
  The UI never claims exhaustive semantic search.
- All returned message IDs and excerpts are **evidence candidates**, not
  verified facts; their original messages can be opened through the existing
  FCC-2c.1 modal with renewed per-message membership, consent and DLP checks.

Semantics: a conservative RU/EN, rule-only classifier attaches tentative
`proposal / confirmation_candidate / revocation_candidate /
rejection_candidate / mixed_requires_review / undetermined` labels.
Known negative phrases are stripped before testing positive approval cues.
Potential conflicts are suggested only for a confirmation candidate opposed
by a revocation/rejection candidate with at least two shared meaningful
terms; both source IDs are shown for review. Quoting, irony, linguistic
ambiguity, topic identity, source authority and consensus cannot be settled
by these lexical rules. A participant saying "approved" does **not** make
a binding room decision. No confirmed/approved claim is persisted.

UI: the existing history-coverage tile contains a collapsed "Search evidence
and decisions" section. Opening it does not search. Submitting sends an
explicit CSRF-protected POST, shows read-only candidates and provenance,
and supports modal source inspection; closing the coverage section aborts
requests and clears local results. RU/EN/ES/HY UI strings are supported,
while the speech-act heuristics are explicitly RU/EN only.

Next required gates before AI synthesis or decision automation: richer
multilingual semantic retrieval with source-grounded structured claims,
cross-message topic/entity resolution, chronology, participant approval
workflow, versioned human confirmation and provider spend estimate.
Keep all provider-payload and human-review gates separate.


## FCC-2e.1: version-checked selected-message chronology and private review marks (2026-11-17)

The existing manual FCC-2d search now additionally returns a bounded
`chronology` derived **only from the up-to-12 ranked matches**. It is
not a semantic decision log, full-room timeline, recorded approval, or
exhaustive extraction of all prior agreements.

- Order: original `messages.created_at` UTC, then stable message ID.
  Creation timestamps are re-read after the second content/consent snapshot;
  an observed timestamp change (even without changing `updated_at`) fails
  closed. A change after final validation still cannot be prevented without
  locks. Whole-room source version and unanimous current consent are checked
  exactly as in FCC-2d.
- Provenance: each candidate records its original message ID, timestamp,
  *pseudonymous* speaker label (`you` or `participant_N` for current room
  members) and tentative RU/EN speech-act cue. We do not expose user IDs,
  attachments, or text of departed/sensitive authors.
- Relation candidates: adjacent relevant earlier/later source pairs with
  two or more shared non-cue terms may be labelled
  `possible_response_to_proposal`, `possible_reversal`, or
  `possible_reconfirmation`. This is **lexical correlation**, not proof
  the messages refer to the same contract, scope, statement, or agreement.
  Mixed/ambiguous text never produces an automatic decision.
- Response explicitly says `approval_state: not_determined`,
  `requires_human_review: true`, and
  `scope: selected_ranked_matches_only`. Existing provider context limit
  of nine excerpts / 2,400 characters and all AI cost and send gates are
  unchanged. No external model call, message send, migration, or persistence.
- UI uses a compact timeline with source buttons opening the existing
  freshly revalidated modal. Optional `Mark as reviewed` toggles are stored
  **only in live Stimulus memory** and are cleared on a new search, folding
  the coverage panel or page reload. They **do not** signify approval,
  participant consensus, or a durable audit record. Human review is a
  separate explicit action; it must not be auto-applied by the classifier.

**Next phase FCC-2e.2** (not included): design a durable, participant-scoped
review workflow with explicit source-version binding, dispute/withdrawal,
consent revocation, and independent server authorization. Do not reuse local
"reviewed" toggles as proof of agreement, write to the message records, or
implicitly forward the timeline to xAI.


## FCC-2e.2a: explicit durable PERSONAL stances (2026-11-17)

This is a separate human-authored review workflow, **not** a decision
engine, shared consensus, contract approval, automated task generator or
authorization to contact an AI provider.

### User contract

An authenticated current member of an eligible private room may explicitly
choose `acknowledged` (this participant personally acknowledges the exact
source message version), `disputed` (this participant objects) or
`withdrawn` (remove their own active stance). Each change creates one
append-only `AiEvidenceReviewEvent`. No review is inferred from the
classifier, chronology, temporary "Reviewed" flag, or other participant's
action. Other participants' statements are not silently approved.

- `room_id, message_id, reviewer_id, source_version_sha256, stance, request_key,
  created_at` are stored. No source text, embeddings, credentials, attachments,
  user names, provider payloads, or private-source copies are persisted.
- The client sends the `source_version` from current eligible results.
  Server strictly recomputes the full consent-bound FCC-2a source inventory
  under the room lock, checks message membership/current author/DLP/body hash,
  verifies source version, then rechecks before transaction commit. Messages
  modified after the final check require fresh validation on the next action.
- Separate `request_key` UUID per explicit action; unique with reviewer ID
  in PostgreSQL. Replaying the latest same action returns the original event;
  repurposing the key fails closed. Repeating an identical current state with
  a new key does not create duplicate events.
- A withdrawal requires a previous active stance on the same source version.
  It is NOT destructive; append-only audit preserves earlier changes. A
  source edit makes old events **stale**, and re-search shows
  `personal_stance: none` until the person acts on the new version.
- Search returns only the requesting user's current-version personal stance.
  It does not disclose other users' private review history. Every response
  explicitly has `room_approval_state: not_determined`; no group approval,
  quorum, notification, AI call, Send, cost or deployment is triggered.
- Deleting a source message, its room, or its reviewer account removes its
  metadata review events through association deletion. Revoking a contextual
  grant blocks search/new review access but does not silently erase the
  append-only personal record; a separate retention/erasure control will be
  specified before production launch.
- UI keeps the separate *ephemeral* "Reviewed" toggle from FCC-2e.1 and now
  adds three explicit actions for each selected source. The current personal
  stance is reloaded on manual search; it is never treated as whole-room
  agreement. Mobile/desktop layout and RU/EN/ES/HY strings provided.

### Rollout

New table migration: `20261117130000_create_ai_evidence_review_events.rb`.
Do **not** reset the database or volumes. The owner's existing modified
`db/schema.rb` has unknown provenance: preserve it, inspect before/after,
and run the additive migration explicitly after full CI passes. Never
overwrite that local file by Git hard reset. Migration currently changes
only this new review-event table; no old records are migrated.

### Remaining gates

FCC-2e.2b: explicit, versioned shared proposals across one or many source
messages; participant-specific acceptance of the exact same proposed terms,
the required quorum, pending/declined/withdrawn transitions, source drift
handling, history erasure/retention policy and per-room synchronization.
Without these gates a collection of personal stances is NOT a confirmed
decision, even if every participant individually clicked "acknowledge".
