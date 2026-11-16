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
