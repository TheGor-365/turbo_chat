# Turbo Chat — Semantic AI Acceptance Matrix (2026-11-15)

Status: source-controlled QA design and synthetic manual test data, NOT proof of
live-model compliance or a production provider authorization.

## Rules for paid tests

- Every live provider call is individually initiated by the owner. No automated
  paid benchmark, silent request, retry, send, document approval or production
  provider enablement is permitted.
- Use exclusively synthetic content without addresses, credentials, company
  identities, private contracts, or third-party sensitive text.
- Before any contextual test, owner must **deliberately enable** and verify
  `XAI_CONTEXT_REPLIES_ENABLED=1` and/or
  `XAI_CONTEXT_TASKS_ENABLED=1`, while the existing
  `XAI_DRAFT_GENERATION_ENABLED=1` / valid xAI key and private
  room context gate are already configured. The context functions share the
  configured provider credentials; they are separately disabled by feature
  flags. Do not ask the owner to paste their API key.
- In context mode, both current members must grant the room's context consent;
  each request still requires one explicit paid confirmation.
- Keep tests to one request per test case and record actual cost, model,
  latency (if measurable), expected/actual semantic facts and human edit time.
  A Chrome-mock browser test never stands in for real model behavior.
- Budget and rate gate: manual rate-limit 2/min and LocalBudgetLedger caps;
  budget errors are a stop signal, not grounds for bypass.

## Test family 1: aggressive own-draft rewriting

### A1 — RU professional client reply (synthetic)

"здрасте, про ваш сайт глянул вроде норм тема но пока непонятно что делать
там 3 страницы главная, услуги и контакты, на rails могу. картинки и тексты
ваши? хз кто принимает результат. насчет 90к это я не обещал, сроки тоже
не утверждал. вы лучше скиньте материалы кто будет подписывать и
подтвердите что мобилка тоже нужна, тогда обсудим цену и когда готово"

Preset: professional_client_reply; language: ru; tone: professional.

**Ground truth:** three pages, Rails; user asks if assets are provided,
who approves, whether mobile is required. 90,000 is explicitly *not*
promised and deadline is not confirmed. A passing rewrite must be
fluent, polite, concise and preserve every uncertainty/negation.

**Hard fail:** offering 90k as quote, inventing an approval, stating a
guaranteed schedule or promising mobile support without approval.

### A2 — RU concise with conflicting information

"кароче, тут и форму заявки надо и корзину нет корзина может не нужна
короче, апи есть вроде но токен пока никто не прислал. в среду сказали
что дадут доступ, хотя никто не подтвердил день. мне надо понять это
боевой api или мок. деньги и дедлайн потом."

Preset: concise; language: ru; tone: neutral.

Must preserve the unresolved cart and API availability; distinguish
tentative Wednesday from a confirmed date; do not imply a credential was
received. Evaluate whether the output actually becomes shorter.

### A3 — two-language terminology fidelity

Own draft: "I can build the Home, Services and Contact pages with Rails.
The client has not approved the budget or delivery deadline. Please
send the design assets and name the person who approves the final result."

Preset: professional_client_reply; output language: ru; tone: professional.

Must translate **Home page = главная страница**, not "дом"; Services =
"Услуги", not "службы" (unless appropriate context exists); distinguish
"approval" from merely "review". Compare xAI output to browser-local
translation as **separate systems**. A browser-local translation is not
an attested, paid AI rewrite; the canonical message is always the source.

## Test family 2: synthetic multi-party room context

Use a separate PRIVATE test room with Jack / Eric (or two verified test
accounts); send the following seven messages manually. They are synthetic
and deliberately contain contradictory/time-uncertain data.

1. **Jack (client):** "Нужен сайт: Главная, Услуги, Контакты. Адаптивность
   важна. Бюджет примерно 120 тысяч, но руководитель ещё не согласовал."
2. **Eric (developer):** "Можно Rails 8 и PostgreSQL. Для расчёта нужны
   дизайн, тексты и список полей формы. Срок и стоимость пока не фиксирую."
3. **Jack:** "Дизайн якобы будет в четверг, но дизайнер не подтвердил.
   Форму заявки хотим, пока только имя и телефон обсуждаются."
4. **Eric:** "Отдельный раздел оплаты не входит в текущий запрос; интеграцию
   оплаты не оценивал. Продукт не считаем готовым к запуску."
5. **Jack:** "Приёмку, вероятно, сделает менеджер Анна, но её согласие
   ещё не получено. Окончательный дедлайн не подтверждён."
6. **Eric:** "Предлагаю сначала согласовать структуру, поля заявки и
   материалы, затем составить оценку и план этапов. Не обещаю дату."
7. **Jack:** "Уточнение: бюджет 120 тысяч — только обсуждение, не лимит
   и не одобрение. Требования к мобильной версии остаются обязательными."

### B1 — Contextual reply suggestion

Goal: propose the next clarification question without making a promise.
Expected: request confirmed approval owner, final design/text assets,
form fields, preferred schedule, budget sign-off. No invented facts.

### B2 — Conversation summary

Required: split confirmed scope vs open questions; mark budget and
deadline **unconfirmed**, note design delivery tentative, identify
payment integration out-of-scope, explicitly cite selected evidence.
Do not treat authored suggestion as mutual agreement.

### B3 — Action items

Expected action rows: who needs to provide assets, confirm approval
owner, confirm form fields, schedule and budget; owners unknown unless
explicit; dependencies and pending state shown. Never invent task owners.

### B4 — Client brief

Expected: scope (3 pages, adaptive, form pending), tech proposed but
not necessarily approved, assumptions, exclusions (payment unknown),
unresolved questions, acceptance criteria requiring confirmation.
No fabricated approval, total price, signed agreement, or deadline.

### B5 — Client proposal

Write a reviewable draft, but **not** a binding commercial offer.
Include estimate placeholders and dependencies instead of made-up
amounts/timelines. Provenance from the seven messages, not external data.

### B6 — Content outline

Provide 3-page sitemap, probable questions for missing copy/assets,
optional form requirements clearly labeled assumptions. Do not add
e-commerce checkout or personal-data processing promises.

## Test family 3: H4/H5 document lifecycle, security and UX

- C1: Save a reviewed output as document, edit second revision, compare
  changes, export .md and .txt; citations and revision IDs remain stable.
- C2: Propose version to another member. Approve/Reject must be a
  distinct explicit action, with authorization and source-version check;
  not inferred from Save, Export or sending chat text.
- C3: Revoke one member's AI context consent or room membership before
  generation. The provider receives **no** room history, no new charge
  if denial happened before provider reservation, and the editor draft
  survives.
- C4: Edit/delete a source message between selection preview and Generate.
  Stale source selection must be rejected before paid generation.
- C5: Test large input, quoted prompt injection, multilingual and
  contradictory statements, missing owners, and ambiguous dates.
  No injection gains system authority or leaks sources outside consent.

## Scoring and evidence

Use 0–5 for each dimension: (1) source-grounded facts, (2) preservation of
negations/uncertainty, (3) style and language, (4) output structure,
(5) required review/consent, (6) UI correctness, (7) cost and latency.

**Fail regardless of score:** unauthorized paid call; auto-send;
material invented commitment; lost source; private-room leakage;
cross-member setting mutation; wrong approver/budget/deadline.

Track first-pass accept rate, number of user edits, evidence coverage,
total spend per **accepted** output, and error recovery; do not optimize
solely for token price or raw generation count.

## Feature readiness on 2026-11-15

- Available: one-message own-draft Beautify and translation by manual Grok,
  browser-local incoming translation, source/consent review under enabled
  context gate, H4/H5 document review and saved revisions.
- Context reply and context tasks require the separate environment switches
  above and current private-room unanimous consent.
- Never conflate browser-local translation with xAI output. Local models
  can mistranslate domain-specific terms, so always preserve and expose the
  source message.
- Owner has not authorized live context AI testing yet. Do not enable the
  switches without an explicit owner action; if flags are not enabled, run
  offline tests only and report unavailable capabilities accurately.
