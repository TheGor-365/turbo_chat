# AI evidence quality matrix — H3g.9c / November 11, 2026

Status: code-backed offline structural checks; NOT a semantic fact-check or production sign-off.
These checks run only after explicitly approved inference. No second provider request, new Message, persisted chat excerpt or automatic Send.

| Scenario | Expected signal | Scope |
| --- | --- | --- |
| Correct M29 source in selected private room | linked_lines | Structural, not truth |
| Nonexistent, foreign or malformed M references | ProviderUnavailable | Hard reject |
| Uncited declarative bullet | no_citation | Advisory |
| Unknown deadline, scope or budget | needs_confirmation | Advisory |
| Source with no meaningful lexical overlap | weak_lexical_overlap | Advisory; translations can be valid |
| Cited statement that contradicts evidence with matching words | structural_only_not_fact_checked | Cannot detect semantic contradiction |
| Invented URL, explicit price or ISO date | Existing ReplyOutputGuard | Hard reject if absent from approved input |
| RU, EN and Armenian sentences | Consistent structural rules | No translation correctness guarantee |
| Question or fenced code | Not an asserted fact | Code citations ignored |
| Revoked membership or expired source selection | Existing ACL/SourceSelection | Hard reject |

Report fields: numeric line counts, referenced source IDs, bounded issue codes and line numbers. No private source text included.
Known limitations: citation may be valid but wrong, inverted, irrelevant, outdated or contradictory. Lexical overlap is not semantic entailment.
Typed confirmed/inferred/unknown facts, human approval, provenance persistence and version history remain H4/H5 gates.