# ADR — Context coverage, scoped room instructions and expressive content (2026-11-15)

Status: **approved product requirements / architectural design only**. No code
for new history access, file transfer, provider tools, or auto media in this
commit. Security limits in running application remain unchanged.

## Evidence-based current implementation

- Provider: `AiWorkspace::Providers::XaiResponses`, `grok-4.3`,
  `POST https://api.x.ai/v1/responses`, `store: false`, `tools: []`,
  `reasoning: {effort: "none"}`; same endpoint for manual draft, contextual
  reply, and contextual document tasks.
- `generate!`: exactly one own-draft row, no chat history or files.
- `ReplyContextBuilder`: scan at most 240 recent candidate messages,
  choose at most 9 text rows/2,400 characters; `omitted` reports scanned
  omissions only. Source consent is currently all current participants of
  a private room (2–10) with explicit grant; member access and source
  selection are revalidated at dispatch.
- Quick per-message language/style/tone, per-member room preferences,
  local-only template hints (max 700 chars), offline original translation,
  and separate versioned document review exist.
- No full-history guarantee, current document/image instructions support,
  or automatic expressive GIF/meme generation exists. The owner observed
  two successful synthetic Grok calls; that is not a semantic benchmark.

## Goal: Full Conversation Coverage, without false promises

A user's phrase "AI should see the whole chat" means the assistant
must *account for every eligible source message* and surface knowledge
coverage. It does NOT mean every raw text byte can fit in a single request.
Non-overridable boundaries:
1. Never send another member's messages to an external model until **all
   current members** explicitly consent, and only in an access-checked
   private room. Public rooms and unjoined users are not eligible.
2. Mode switch **Own draft only / Conversation context** must be visible.
   Own-draft Beautify never silently begins including room history.
3. When contextual generation is authorized, backend covers all eligible
   room history (paginate by stable snapshot cursor), excluding messages
   outside current access, retracted/removed sources and flagged secrets.
   A snapshot ledger records total, scanned, eligible, included, filtered,
   truncated, evidence IDs, and reason. The UI displays actual coverage.
4. For short conversations under budget: direct chronological context.
   For long conversations: hierarchical time-window summaries plus
   evidence retrieval and contradiction/decision indexes. Canonical
   messages remain the source of truth; each generated fact has a message
   reference. Summaries are invalidated on source edits/deletes, access
   revocation, new messages, or rule changes. Never claim 100% raw coverage
   if any eligible source was unavailable.
5. Versioned `ContextSnapshot` and deterministic `CoverageReport`.
   Include snapshot ID/hash and source window in provenance, preview,
   any saved deliverable, and approval/Reject lifecycle.
6. Token estimation, provider context window, request TPM/RPM, LocalBudgetLedger
   and explicit charge ceiling are checked **before** sending. The currently
   configured user key screenshot shows 2 RPM and 10,000 TPM; this can
   preclude large raw-history requests even if the model supports a much
   larger context window. Show a truthful downgrade or block rather than
   silently truncating. No automatic provider retries.
7. Files/attachments do not inherit consent from text. They have separate
   opt-in/preview, source type, allowed MIME, malware/PII screening,
   signed local URLs, and retention/deletion policy. Do not send private
   files or original external-API document references without consent.

## Room AI instructions: 3 explicit scopes

- **Account defaults:** user's own preferences (future Account Preferences).
- **Room instructions:** room-specific purpose, terminology, preferred format,
  glossary, exclusions and business constraints, attached to room with
  membership/owner or moderator-controlled editing policy and revision
  history. Plain text first. Any participant may view the current effective
  config, but only authorized editors may change it.
- **One-request instructions:** temporary per-request text/preset/reference,
  scoped to current author and never mutating room or account defaults.

Payload priority: immutable safety policy > explicit user task > current
authorized room policy > personal style; untrusted room-history excerpts,
uploaded documents, and retrieved text are **data**, not instructions.
A message's proposed price does not override a signed/confirmed agreement;
model must mark unknowns.

**Text V1:** editable content (length limit, sanitized), versioned
`RoomAiInstruction` record, Pundit-/controller-enforced membership and edit
authorization, optimistic lock, audit/change log, tests for cross-room access.
A preference is NOT provider spend consent. Include instruction digest in
generation snapshot and show exact preview; changing instructions invalidates
stale previews.

**File V2:** upload text, PDF/DOCX and images under Active Storage with
whitelisted types/byte limits; local extraction and per-file owner permission,
OCR/image understanding only through explicitly selected supported pipelines
and endpoint permissions. Document versions and retention tied to room.
Provider Files API is an optional later integration, not a requirement for
generating text documents. Never assume the current key has Files/Image
permissions or tell the user to enable all endpoints.

## Expressive message enhancement

Separate **professional rewriting** from **expressive formatting**.
Proposed `expressive` preset controls: emoji density 0/low/medium,
structured readability, optional icon-like markers, humour level,
audience-safe language. It must preserve all facts, dates, negations,
links and prices, and never assume playful tone in business/professional
context without explicit author choice.

GIF/meme capability is a *separate* rights-aware media picker with provider
license/attribution, moderate file size, safe-search, alt text, and
user-confirmed attachment. Never synthesize a fake media URL or upload
generated media on mere Beautify; no automatic external search or expenses.
Model may suggest keywords, but selection and Send stay user controlled.

## Delivery stages / tests

1. Visual toggle standardization (implemented separately); local accept.
2. Account defaults + effective-settings provenance (small new migration;
   guard `db/schema.rb`, backup before applying).
3. Room Instructions V1 (plain text, revisions, access control, no provider
   calls) and one-request hint precedence. Then consented provider snapshot.
4. Full-history coverage index/snapshot and visible coverage report
   replacing the 9-message/2,400-char **limit** only after security/cost
   acceptance. Cross-member revoke, edit/delete, adversarial large history
   and provider 10k TPM limit must be tested.
5. Document/image file ingestion as isolated opt-in feature, text first,
   separate provider permissions only when needed.
6. Expressive emoji preset and optional GIF/meme picker, copyright/safety
   review, 320px/desktop UX. No auto-send.
7. Semantic evaluation with synthetic multi-party conversation matrix and
   measurable first-pass accepted output, factual fidelity, completeness,
   source coverage, cost per accepted result, and time saved.
8. H5 versions/review/Approve-Reject; production budget/privacy hardening,
   then separate user-authorized deployment.

**Explicit non-goals:** automating user consent; bypassing key ACLs;
implicitly transmitting all current room messages on a plain Beautify;
ignoring model context/token limitations; unapproved paid API calls.
