# H4 — Typed deliverables V1 (ephemeral contract)

Date: 2026-11-11. Scope: first H4 engineering slice; not a live UI integration or release acceptance.

## What exists

- AiWorkspace::StructuredDeliverableV1 is an in-memory immutable value contract for client_brief, client_proposal and conversation_summary.
- Each entry carries a code-owned section, bounded text, an explicit state and source_message_ids restricted to a validated ReplyContextBuilder::Bundle.
- Draft input permits inferred, unknown and needs_confirmation. Confirmed is forbidden at draft construction even if an M-reference exists.
- Only an explicit review! call with the originating actor ID and a confirm decision can mark an entry confirmed. This records a human designation, not independent fact verification.
- Document review_state is pending_manual_review or reviewed_not_approved. Review is NOT approval, publication or Send.
- The contract has no migrations, network calls, model calls, persistence, Messages or billing effects. No server endpoint or UI button is introduced in this slice.

## Typed sections

| Kind | Allowed sections |
| --- | --- |
| client_brief | objective, audience, requirements, constraints, deliverables, acceptance_criteria, open_questions |
| client_proposal | problem, approach, deliverables, exclusions, assumptions, next_steps |
| conversation_summary | summary, decisions, open_questions, next_steps |

## Status semantics

| State | Meaning |
| --- | --- |
| inferred | Draft interpretation/working hypothesis. Even a source ID does not validate semantic entailment. |
| unknown | Information is absent or insufficient. |
| needs_confirmation | A specific decision/detail must be checked with a human. |
| confirmed | Explicitly marked by a reviewer via review!, not inferred from citation or lexical overlap. |

All unreviewed entries initially have reviewed_by_actor_id = nil. The manual review transition attaches a reviewer actor ID while preserving permitted source IDs and the original text. Returning all entries as reviewed_not_approved does not authorize sending or external use.

## Validation and privacy boundaries

- Input is explicitly structured Ruby entries; it is NOT a parser or validator of arbitrary provider Markdown. No automatic translation of a generated response into this schema is implemented yet.
- Source IDs must be part of the same pre-authorized bundle. Embedded [M...] citations must belong to that entry's source list. Other IDs and malformed M-tags are rejected.
- Entry text is limited to 600 characters, total entries to 36, allowed source count to the existing ReplyContextBuilder limit.
- Claim content is intentionally present in the in-memory document for human review; do not log or upload it. Error messages do not echo private text.
- review! checks originating actor ID but deliberately does not replace live room membership/consent authorization. A future controller must re-check ACL and revocation before showing any private content or allowing review.
- Neither a human-confirmed label nor EvidenceReviewV1's structural assessment proves truth, source relevance, or legal/business agreement.
- UI must escape/render content safely; this service does not authorize raw HTML rendering.

## Next H4 gates

1. Build a bounded, deterministic adapter from the existing guarded AI output to typed entries; never classify a claim as confirmed automatically. Prefer no additional paid request.
2. Add a visible manual Review surface with clearly separated inferred/unknown/needs confirmation/confirmed, direct access to authorized source evidence, and safe editing.
3. Authorize every review and source access in live room context, covering revoke/remove/leave, stale drafts, two users, and XSS; preserve manual Apply/Send.
4. Run exact-SHA tests and owner UX acceptance. Persistent approval/version storage remains H5 and requires a separate migration/backup gate.

Current exclusions: no database migration, no PR merge, no Railway deployment, no provider call, no automated Send, no background agent.
