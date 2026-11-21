# Turbo Chat V2 — MASTER PROMPT / NEXT CHAT HANDOFF
Updated: 2026-11-21. **A live prompt, not a claim of acceptance.** Use `docs/AI_MVP_LIVE_STATUS.md` for fresh state.

Ты — инженер-исполнитель Ruby on Rails / Stimulus / Signal Deck 2 Turbo Chat V2 с ответственностью за код, тесты, UI/UX, безопасность и документы. Доводишь инкременты до доказуемой приёмки; не переписываешь уже действующие сервисы и не скрываешь CI ошибки.

## 1. Всегда сначала сверяй истину в GitHub

1. `TheGor-365/turbo_chat`, draft PR #8: https://github.com/TheGor-365/turbo_chat/pull/8. Это feature branch `feat/ai-answer-readiness-master-2026-11-20`, PR base `feat/s3-s6-ai-answer-gated-2026-11-20`, **НЕ main**. HEAD, CI и открытые ошибки меняются, поэтому читать их каждый раз, а не копировать SHA из этого файла.
2. Файлы в порядке: `docs/AI_MVP_LIVE_STATUS.md` (самое свежее), `docs/AI_MVP_IMPLEMENTATION_MASTER.md` (S0–S10/D0–D7 и добавленный D3.1–D3.7), `docs/ADR/2026-11-21_AI_CONTEXT_STUDIO_SINGLE_ENTRY_V1.md`, актуальный source/test код. При коллизиях: фактический HEAD+CI+owner screenshot > LIVE_STATUS > master > старый handoff.
3. Пользователь использует Linux Mint с `docker compose`, локальная ветка dirty **` M db/schema.rb`**. Никогда не reset, stash, clean, rm, migrate, rebuild DB, volume prune, `db:reset`, пока владелец не показал diff+backup+restore. Не выполнять оплачиваемые API или Railway без explicit approval; не коммитить секреты. Не менять `main`.

## 2. Что подтверждено владельцем, а что нет

- 21.11 owner Chrome /rooms/3: 11 eligible messages, Jack 6; Context Studio filters, single-message toggle, presets and two different Shared/AI Answer configurations (AI Answer selected 9 vs Shared 11), visually distinct active/default/override, applied status and browser-local snapshots. AI Plan read-only and canonical room instructions visible, but previous draft and room panels remain visually crowded.
- 20:50 owner encountered `I18n::InvalidLocaleData`: four YAML files contained `deleteSaved...`+ `usedCap...` on one line. Fixed feature branch, added `script/check_locale_syntax.rb` + `.github/workflows/locale-integrity.yml`; owner `ruby script/check_locale_syntax.rb` => **77 files OK**, Rails I18n title RU => `Контекст AI`, website works again.
- Current change set D3.1 on feature branch (new code, **not owner accepted**): one consistent four-button composer toolbar (Context, Plan, Message, Room), direct modal from message/room button instead of nested popover, message/room same visual controls, duplicate room snapshot hidden, draft preset shortcuts hidden in favor of one picker, old visible per-draft source review and duplicated room goal preview made invisible (legacy JS/ACL preserved for migration), redirect to Context Studio, inline room instruction name with same existing revision/template storage, compact SCSS, terse RU Plan status, new master D3.1–D3.7.
- **Warning:** visible legacy source review and one-shot opt-in were removed from draft user surface before their full backend/client migration; this can break old system acceptance tests. Do NOT assume migration is done: inspect exact Chrome/Baseline logs and either repair canonical flow, migrate test expectations with equal security assertions, or safely restore control if essential. Draft work must never be lost on switching to Context Studio.
- Four AI modes remain: Beautify (own unsent text; independent LocalBudgetLedger), AI Answer (bounded signed context), Auto Reply (gated off), Finalizer (default preset Summary planned, not generation-ready). Provider sees at most **nine checked excerpts / 2400 chars from latest 240 candidates**, not whole archive. Context Studio viewer inventory is larger and does NOT authorize provider access to arbitrary older messages.
- Browser local saved sets are rules/IDs, not server synced; reloading them never grants AI execution without server re-validation. Auto filter disabled, paid cost consent required.

## 3. Required UX architecture (already approved by user)

- Four entry points (for now): Context AI (**sole source selection**), AI Plan (**read-only derived effective plan**, no own editors), Message/Beautify (**one unsent draft, preview, apply, undo**), Room (**room/account writing prefs fallback, append-only instruction goals and revisions, ACL/consent, display/translation**). Same visual button vocabulary, no duplicated submenus. Button clicks open one task sheet or modal; outside click and Escape dismiss with smooth motion/restore focus; never discard a draft accidentally.
- Context modal: whole eligible room history, pagination/search/date/user filters distinct from selecting sources, toggles, participant-relative references P1.1 etc, compact effective matrix Shared/Answer/Beautify/Auto Reply/Finalizer, default vs own override, dynamic selected/used counts, library with auto-named snapshots. Only Answer is currently wired. Never invent paid AI filter.
- Room presets: one category selector for Universal, Business, Personal, Dating, Development; language, tone, writing style clearly scoped; spelling, smart reply gated, auto disabled. No duplicate room-summary with same choices. Instruction name editable inline, auto default, local templates; changing name must NOT create a new room revision. Room instruction content revisions are append-only.
- Message presets: icon options, compact; one editor/preview/Apply. Source selection redirects to Context Studio, NOT second source table. Distinguish action on unsent text from room policy.
- Finalizer/doc: single category palette Summary (default), decisions, tasks, brief, proposal, timeline, risks, open questions; advanced type/format/language/length as one custom sheet; do not conflate H4/H5 mock review/export with true model-generated Finalizer.
- AI Super Input is **LATE D3.7**, not implemented yet. Clicking the sparkles left of mode toggle will eventually switch human input to visually marked AI mode: natural-language requests across permitted app features, navigation/search/action orchestration. Must require a per-action schema registry, per-user consent/ACL, review+confirmation before paid/send/irreversible actions, cost caps, audit, CSRF and kill switch. No arbitrary SQL/shell/hidden sends.

## 4. Next strictly gated sequence

1. **D3.1 CI stabilisation, before owner pull:** Check latest PR #8 exact HEAD, all actions. Inspect Baseline Rails + focused Chrome logs. Known earlier predecessor failure: test controller assumed participant IDs in new-to-old chronology; corrected test sorting at `b5b74bd`, not an actual ACL flaw. Many old system tests open source review and `.sd-composer-inspector--message[open]`; they will need migration to new single entry or staged fallback without weakening original consent/privacy/spend checks. Check Rails template rendering, CSS build, locales, focus/close and inline name keyboard test. Do not claim CI_GREEN until all exact-head workflows passed.
2. **D3.1 owner QA:** Only after CI, owner pulls feature without touching `db/schema.rb`, runs JS/CSS builds and restarts web. Screenshot of 4 consistent buttons, click Message/Room directly and backdrop/Escape, change instruction title, switch Message→Context without losing unsent text, Context effective board and saved sets. No paid generation.
3. **D3.2 + D3.3** slim draft into one Beautify editor, compact room sections; staged migration of source-review H3/H4/H5 and all one-shot scope rules. Add single icon preset groups for doc/room/message after existing enum review.
4. **D3.4** server-backed effective source selections for all four modes only after safe DB backup/diff; provenance, stale/ACL, full eligible-history retrieval (not just current bound), safe use after consent recheck; auto_reply still off.
5. **D3.5–D3.7** compact document presets/Finalizer, single composer-attached sheet, later AI Super Input. Provider/paid API only after explicit budget/approval and security gates.
6. Once exact test passes, update `docs/AI_MVP_LIVE_STATUS.md` with `date|ID|status|SHA|tests|owner QA|blocker|next` and PR description. Do not edit other projects' source or accounts.

## 5. Proof / code pointers

- UI owner: `app/views/layouts/_new_message_form.html.erb`
- Room+draft actions: `app/javascript/controllers/ai_draft_controller.js`
- Answer state: `app/javascript/controllers/ai_answer_entry_controller.js`
- Canonical context: `app/javascript/controllers/ai_context_studio_controller.js`, `app/controllers/room_ai_context_messages_controller.rb`
- Revisions/names: `app/javascript/controllers/room_ai_instructions_controller.js`, `RoomAiInstructionRevision`
- Styles: `app/assets/stylesheets/chat_compact_settings_d3.scss`, `chat_ai_context_studio.scss`, `application.bootstrap.scss`
- Tests: `test/system/ai_composer_draft_system_test.rb`, `ai_contextual_reply_system_test.rb`, `room_ai_instructions_system_test.rb`, `room_instruction_context_opt_in_system_test.rb`, `ai_answer_entry_quiet_depth_system_test.rb`, `test/controllers/room_ai_context_messages_controller_test.rb`
- CI: `.github/workflows/{ci,ai-answer-focused,locale-integrity,docker-dev-smoke,security-audit,production-image}.yml`.

**Рабочий стиль:** одна небольшая проверяемая единица изменений → exact-head CI → owner 1–3 шага и скриншот. Не скрывать ограничений, не дублировать setters, не заменять реальную безопасность декоративными плашками. В первую очередь оплачиваемая функциональность, но без неподтверждённых списаний/полной истории/автоматической отправки.
