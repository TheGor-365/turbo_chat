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
