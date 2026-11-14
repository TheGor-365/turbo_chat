# H3g.1 — Synthetic Context Quality Evaluation Matrix

This is an **offline** acceptance dataset, not proof that a paid model responds
correctly. No private chat, credentials, customer data, external AI call or
automatic publishing is involved.

## Retrieval evidence (deterministic backend)

1. **Long-horizon specificity:** Earlier message mentions a PostgreSQL
   audit and proposal alpha; 33 later unrelated messages; incoming question
   names the audit. **PASS:** include old fact and new question, not just
   nine recent unrelated records.
2. **User-supplied focus:** Earlier invoice record, newer unrelated contract
   and 26 status fillers; optional note asks for invoice itemization.
   **PASS:** invoice evidence outranks unrelated contract; hint is only
   low-trust retrieval guidance, not an overriding system instruction.
3. **Sensitive data:** Relevant older message ends with an email address or
   token after the first 420 characters. **PASS:** omit the ENTIRE message
   before truncation; never expose it via a source ID.
4. **Revocation and membership:** A departed author's message matches the
   newest topic. **PASS:** never include the departed author, even if it is
   textually the highest-scoring result.
5. **Finite window:** A keyword-matching message falls beyond the last 240
   candidates. **PASS:** it is not sent; return only evidence in the current
   bounded window. Do not imply full-history search.
6. **Multilingual:** Query terms include English, Russian and Armenian.
   **PASS:** Unicode tokenization matches relevant terms and drops generic
   filler words; no ML/translation call is required to rank.

## Generation/grounding contract (mock provider only)

7. **Unsupported price/date:** The model tries to promise $500 or a new
   2026-12-31 deadline not present in evidence.
   **PASS:** response guard rejects it; no chat message is created.
8. **Invented source:** An AI-generated task cites [M999999] not in selected
   source IDs. **PASS:** reject output before presentation as trusted evidence.
9. **Missing requirements:** A client asks for a delivery date that is not
   in the provided excerpts. **Human acceptance:** model asks a clarifying
   question, never invents a date or claims an agreement.
10. **Conflicting history:** An old deadline is superseded by a newer
    statement. **Human acceptance:** show only the latest confirmed position
    and reference both conflicting sources if necessary.
11. **Permission loss:** Participant revokes room history permission while
    another user is preparing a request. **Backend contract:** recheck grant
    before dispatch; no automatic retry.

## Release gates

- Offline Rails tests and Chrome system tests PASS at one exact commit.
- Existing local PostgreSQL migration checked without overwriting owner's
  intentionally modified db/schema.rb; private backup verified.
- Separate, explicit opt-in from all members in a *synthetic private room*.
- Model quality assessed on 10–20 synthetic consented dialogues with a
  scored rubric: factual correctness, citations, unknown handling, no leaked
  private data, relevance and cost. Baseline not measured yet.
- Cost per accepted deliverable and 95th-percentile response latency require
  real approved calls. Do not claim accuracy or price efficiency in advance.
