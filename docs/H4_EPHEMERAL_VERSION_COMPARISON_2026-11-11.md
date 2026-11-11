# H4 — Ephemeral version comparison / H5 persistence gate

Date: 2026-11-11. Reference style: Signal Deck `/notifications`.

## Implemented

- After a document is parsed into typed H4 statements, a separate **Compare a revision** editor appears. It starts with a copy of the original Markdown, so the user can edit only the proposed version.
- Submitting comparison performs a new authenticated, consent-gated POST and rebuilds the `ReplyContextBuilder` source bundle. Both original and proposed Markdown are parsed separately with identical room, actor and source restrictions.
- `StructuredDeliverableComparisonV1` compares occurrences of exact triples: (section, text, cited source IDs). It reports unchanged, removed and added statements, including duplicates. A rewritten sentence counts as one removal and one addition. There is deliberately no semantic equivalence, AI inference or automatic confirmation.
- Both versions and the diff exist only in memory for the current HTTP response; nothing is stored. Human review choices are not silently transferred to changed statements. `Confirm` is an independent explicit manual action, not an approval.
- All references in both versions are reauthorized. The response retains private `Cache-Control: private, no-store`, HTML escaping and existing Signal Deck styles.
- The review, comparison, Apply, Undo, Send, export and provider generation remain distinct. No Grok request, database migration, Railway deployment, PR merge or existing asset deletion.

## Acceptance checklist

1. In local room with consent 2/2, open `/rooms/3/ai/deliverable-review?demo=1`, click inspect arrow, scroll down to **Compare a revision**.
2. Change `- Budget: To confirm` to `- Budget: Needs client confirmation` in **Proposed version**; click the round-arrow compare icon.
3. Expect **4 unchanged, 1 added, 1 removed**, with original and replacement text shown. It must not send a chat message or mark any claim approved.
4. Verify that revoked consent/removed membership causes forbidden POST, and unknown `[M...]` tags fail closed.
5. Require exact-SHA Rails CI, Security audit and Docker smoke checks before marking this stage fully accepted. Separately inspect pending H7 realtime tests.

## Future H5 only after explicit approval

Persistent document versions, authorship/audit logs, approval workflow, signed snapshots, sharing, retention, rollback and actual database migrations have **not** been built. They require a separate schema design, migration/backup approval, access-control review, and release plan.
