# AI Beautify — semantic quality acceptance baseline / 2026-11-15

**Status:** evaluation contract, not evidence that Grok has passed. The owner
performs only manually initiated paid tests using synthetic texts. There is
no automatic test traffic to a paid provider or customer-data storage.

## Baseline scenario: RU business reply from an unsent synthetic draft

Room profile Business, language Russian, tone Professional, style
`professional_client_reply`. Draft:

> здраствуйте, посмотрел ваш запрос на сайт. могу сделать главную, услуги и контакты на rails. дизайн и тексты вы еще не дали, поэтому цену и сроки пока не скажу. сначала пришлите материалы и скажите кто будет утверждать результат. после этого обсудим стоимость и время работы.

Explicit input facts: Rails website; three requested pages Home, Services,
Contacts; design/text not supplied; price and timing not agreed;
request materials and identify acceptance owner before discussing scope/cost.
No client identity or personal information is present.

## Release-quality rubric

| Category | Weight | Passing evidence |
|---|---:|---|
| Semantic preservation & safe commitments | 40% | All input facts and sequence survive; no invented prices, delivery dates, agreements, site completion, prior client relationship |
| Linguistic accuracy & actionability | 25% | Correct Russian spelling and punctuation; clear professional wording; actionable request for missing materials/approval |
| Selected style, language, tone | 15% | RU output; professional tone; no gratuitous translation, new facts, greetings/closing that invent a relationship |
| UX reliability | 10% | Unsent original persists; AI version distinct/editable; settings icon opens without paid calls; Regenerate disabled until changed options; invalidated candidate never sent |
| Cost transparency | 10% | One user action = at most one provider request; response reports metered cost; failed/ambiguous provider outcome shown without silent retries |

**Hard-fail:** accidental chat Send; secret or other-member data to provider;
unsupported factual commitment; paid request without a direct user action;
cross-user/cross-room state exposure. Score alone cannot override a hard fail.
Do not claim semantic correctness from tests that only assert prompt strings.
A passing mock Chrome test is a UI contract, not live-model quality evidence.

## Empirical check (no extra paid call unless owner explicitly requests)

1. First call: store only synthetic input, chosen options, exact visibly
   returned text, displayed `cost_usd`, error state (if any), and observed UI.
   Screenshots should exclude personal credentials/client data.
2. Manually compare every source claim against generated result; mark
   **preserved / softened / contradicted / invented / omitted**, with evidence.
3. Only if first result fails on tone/style, change one option and manually
   Regenerate once, respecting the 2/min throttle and per-user/installation
   LocalBudgetLedger limits. No repeat merely for randomness.
4. Investigate first failure by locus: prompt wording, preset/locale
   resolution, server validation, provider transport, browser state, or
   document/Send authorization. Prefer a narrow code-owned prompt revision
   with adversarial offline tests to changing model/temperature blindly.

## Known code-level limitations to address before production

- `ManualDraftGeneration.enabled?` is development-only; production
  consent, multi-host budget accounting, provider retention and operational
  privacy are not completed. Local demo is not a commercial deployment.
- `DraftPromptV1` has style instructions such as "original language",
  potentially conflicting with an explicit alternate output language. Test
  multilingual scenarios and specify priority in a later versioned prompt
  refinement; do not silently alter the owner baseline before observing it.
- Provider-side nondeterminism can still occur even with identical inputs;
  UX prevents same-settings regeneration as a product/cost policy, not as a
  mathematical guarantee of identical model text.
- A served AI result can be edited before human-controlled Send. The
  existing provenance attests source output, not independent semantic truth.

## First live synthetic observation and targeted prompt maintenance

Owner screenshots on 2026-11-15 show:
- First Russian result under the **Eric** account used
  `polish_clarity / auto / neutral`, not Jack's Business profile.
  It repaired the misspelling of "здраствуйте" but left lowercase starts
  of later sentences. This falls short of full proofread acceptance even
  though a minimal rewrite is correct for the selected mode.
- The second request used `concise / en / professional` and produced
  a meaning-preserving English version. Price and deadline stayed unknown.
- Chrome's separate **on-device incoming translation** rendered English
  "home" as Russian "дома" instead of "Главная страница" and
  "services" as "службы". This is **not** a Grok error; the canonical
  English source remained accessible and the UI now explicitly warns
  that browser-local translation may distort technical terminology.
- No claims of provider reliability can be inferred from only two
  observed live calls. Prompt changes need repeatable independent tests.

Prompt maintenance: `DraftPromptV1::POLISH` now explicitly requests
sentence-start capitalization and normalization of unambiguous conventional
technology names (such as Ruby on Rails), with guards against inventing
technology. Its low-change proofreading semantics remain intact; this is
a narrowly scoped quality fix rather than a model or budget change.
