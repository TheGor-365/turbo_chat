# TURBO CHAT V2 — LIVE STATUS / ЕДИНАЯ ТОЧКА ПРОДОЛЖЕНИЯ
**Снимок проверки:** 2026-11-21. **Сначала перепроверь HEAD, PR #8, Actions и код!** Эта запись не автообновляется после чужих коммитов.
**Продуктовый master:** [AI_MVP_IMPLEMENTATION_MASTER.md](./AI_MVP_IMPLEMENTATION_MASTER.md).
**Текущая ветка:** `feat/ai-answer-readiness-master-2026-11-20`.
**PR #8:** https://github.com/TheGor-365/turbo_chat/pull/8 — draft, open, base `feat/s3-s6-ai-answer-gated-2026-11-20`, `main` не затронут.

## A. Последний реально наблюдавшийся owner state (не выдумывать новые факты)
- Owner terminal 21.11: fast-forward `a231da4 → 2b7dcd3` SUCCESS; `docker compose exec -T web yarn build`, `yarn build:css`, `docker compose restart web` SUCCESS; `docker compose ps`: web Up, db healthy, Redis Up. Отдельный owner screenshot `/rooms/3` показал прежний in-Plan editor M29–M37 — это основание D5.1 redesign, НЕ приёмка нового UI.
- Owner `git status --short`: ` M db/schema.rb` — модифицирован; **НЕ трогать**. Причина не изучена; до новых миграций нужен локальный backup.
- UI **после** a231da4 владельцем не проверен: M35 → M33, кастомные dropdown, успешное «Применено», смена языка/стиля и отсутствие мерцания — `OWNER_QA_PENDING`.
- Evidence M33/M34 persist/revoke, local PG+media backup/restore — `OWNER_QA_PENDING / NOT_VERIFIED`.
- Production xAI/Turbo Chat Railway R0/R1 не заявлены работающими.

## B. Достоверный CI на исходном кодовом a231da4
GitHub Actions проверены 21.11 на точном `a231da419d5cf0aaa138c425adf2a6feee63443e`:
| Workflow | Run ID | Результат |
|---|---|---|
| Local Docker Compose smoke | 44854270867 | SUCCESS |
| Security audit | 44854270929 | SUCCESS |
| Production image build (no deploy) | 44854270846 | SUCCESS |
| AI Answer / Quiet Depth focused Chrome | 44854270844 | FAILURE |
| Baseline Rails CI | 44854270909 | FAILURE |

**Результат оба fail workflow:** 3 одних и тех же сценария из `test/system/ai_answer_entry_quiet_depth_system_test.rb`:
- line 217 — ожидание *visible* `select[data-plan-field='profile_id']`, хотя `ui-select` скрывает native-backed select и выводит фирменный popup.
- line 282 — аналогично *visible* `select[data-plan-field='reply_target_id']`.
- line 266 — новая room instruction revision реально создаётся (проверка количества/контента проходит), но `.sd-ai-plan-edit__feedback[data-state='saved']` не виден: feedback лежал **внутри closed <details>** после перерендера. Это реальная UX-ошибка, не повод ослаблять assertion.
Focused Chrome summary: **55 tests, 796 assertions, 3 failures, 0 errors**.
Обычные записи PostgreSQL `duplicate key` в teardown/log не следует объявлять первопричиной этих трёх тестовых отказов без отдельного доказательства.

## C. Изменения этой сессии, откуда продолжать
| ID | Commit SHA | Path | Результат / доказательство |
|---|---|---|---|
| T1.3/S2.5 | `6a13ea9f6cec6c80126d35b429363c6df5bd2bf0` | `app/javascript/controllers/ai_answer_entry_controller.js` | Вынесен `goal` saved feedback наружу из `<details>`; при закрытии editor уведомление должно оставаться видимым. Узкая правка |
| T1.3/TEST | `b530f9dd92615c29836b8eb27eb8135252216e48` | `test/system/ai_answer_entry_quiet_depth_system_test.rb` | Две проверки native `select` используют `visible: :all`; проверка видимого Signal Deck popup осталась; visible saved feedback сохранён |
| DOCS-MASTER | `b5aee3bb321c73d105e8d2c40048b600e590e3d0` | `docs/AI_MVP_IMPLEMENTATION_MASTER.md` | Полный 4-mode master/roadmap. Само создание документа не доказывает ни одной новой AI-функции |

**Текущий документ намеренно не утверждает, что CI этих новых коммитов зелёный.** Проверить Actions на последнем фактическом HEAD после записи этого LIVE_STATUS. `OWNER_QA_PENDING` до живого Chrome-теста.

## D. Карта внедрения по ID (это не TODO без сверки кода)
Легенда: `EXISTS_CODE` = класс/flow существует, не обязательно принят; `PARTIAL` = незавершён; `SPEC` = требование; `CI_FAILED` = fail на исходном HEAD; `OWNER_QA_PENDING` = нужно подтверждение локальным браузером; `BLOCKED` = запрещено продолжать до gate.

| ID | Состояние на 21.11 | Подтверждение/остаток |
|---|---|---|
| S0.1 | PARTIAL / OWNER_QA_PENDING | Evidence search + M33/M34 уже разработан ранее; confirm/revoke/research вручную ещё не проверены |
| S0.2 | BLOCKED | `M db/schema.rb`; текущий локальный PG/media backup+restore не предъявлен |
| S0.3 | OWNER_QA_PENDING | owner не открывал экран после a231da4 |
| S0.4 | EXISTS_CODE | ADR 2026-11-20 и новый master; проверить актуальность перед каждым циклом |
| S1.1 | EXISTS_CODE | JS переключает Answer (empty) / Beautify (typed); без нового provider |
| S1.2 | EXISTS_CODE / OWNER_QA_PENDING | Inline goal/consent/provider blocker в PR #8; не владелец QA |
| S1.3 | EXISTS_CODE / OWNER_QA_PENDING | independent editors/Send/resize/keyboard есть в коде; owner acceptance pending |
| S1.4 | PARTIAL | regenerate, one-shot есть; по mode-aware shared plan ещё не финал |
| S2.1 | EXISTS_CODE / OWNER_QA_PENDING | room instruction revisions и per-room personal goal, ACL/versioning есть; owner multi-tab QA pending |
| S2.2 | PARTIAL | resolver и account/room/one-shot есть; единого cross-mode settings UX пока нет |
| S2.3 | SPEC | shared default + optional independent per-function override ещё проектируется, нет доказанной модели |
| S2.4 | PARTIAL | пресеты/язык/стиль/тон есть, полная modifier catalog/script не готова |
| S2.5 | CI_FAILED@a231da4 → PATCHED_UNVERIFIED@b530f9d | фикс feedback + target selection/SDSelect assertions, ждём exact HEAD CI/owner QA |
| S3.1 | EXISTS_CODE | `GenerationOrchestrator` + `GenerationInputContract` существуют, НЕ создавать второй |
| S3.2 | PARTIAL | Answer typed input/own-draft compile есть; auto_reply запрещён; Finalizer не подключён |
| S3.3 | PARTIAL | bounded selection 240 candidate / 9 excerpts / 2400 chars, НЕ full history |
| S3.4 | PARTIAL | ответная ревизия/consent fingerprints для Answer существуют; единое покрытие всех modes не доказано |
| S3.5 | PARTIAL | Answer provenance exists, Beautify и Finalizer ещё не общая архитектура |
| S6.1 | BLOCKED | Production provider, цена/retention и ключная policy для релиза не утверждены |
| S6.2 | PARTIAL | PG usage ledger для dev Answer есть; Beautify остаётся на `LocalBudgetLedger` |
| S6.3–S6.5 | SPEC / PARTIAL | безопасность Answer частично есть; сквозные квоты/concurrency/production secrets/failover не завершены |
| S4.1–S4.4 | PARTIAL | локальный перевод частично существует; языковые пары и внешний fallback не приняты |
| S5.1–S5.4 | SPEC | отдельной подтверждённой базы знаний/grounded retrieval нет |
| S7.1–S7.5 | SPEC | в старой ветке экспериментальная автоматика, НЕТ разрешения на Auto Send |
| S8.1 | IN_PROGRESS / CI_PENDING / OWNER_QA_PENDING | D5.1 user Chrome partial QA: 11 messages, Jack filter 6 and switch/solo confirmed. D5.2 code adds visual effective board, auto-named browser-local sets, Pn.m references, smooth accordions and scope-presets; server sets/full-history model retrieval NOT built |
| S8.2–S8.4 | SPEC | **AI Finalizer с Summary по умолчанию НЕ реализован**; старая H4/H5 проверка/экспорт != real AI summary |
| S8.5 | PARTIAL | исторические source checks есть, полная инвалидация сохранённых наборов ещё не существует |
| S9.1–S9.4 | BLOCKED | Турбо Чат не подтверждён в отдельном Railway R0/R1 |
| S10.1–S10.4 | SPEC | tenant API/widget/commercial pilot не завершён |
| D0–D2 | PARTIAL | старые Signal Deck UI, theme, native-backed select есть; полный аудит/консолидация token не подтверждены |
| D3 | PARTIAL / QA_PENDING | AI Plan redundant goal + writing preferences editors removed, links to canonical Room settings. Separate legacy contextual-draft source review still exists, needs gated migration; complete cross-mode settings not ready |
| D4 | PARTIAL | RU/EN/ES/HY отдельные slices есть; весь Workspace и Review не принят |
| D5 | IN_PROGRESS / CI_PENDING / OWNER_QA_PENDING | Context Studio D5.2: separated card surfaces, effective scope matrix and default/own/apply state, icon stats, actor/message ordinals, auto-saved LOCAL sets and animated library. Server-synced sets, all-history provider retrieval, AI-filter, four-mode runtime integration still SPEC |
| D6–D7 | SPEC/PARTIAL | отдельные responsive/keyboard тесты есть, полный visual/a11y gate не пройден |

## E. Непосредственно следующий прогон (D5.1, без старых чекбоксов)

**E1 — CI на exact последнем HEAD:** После D5.1 commits проверить PR #8 head и GitHub Actions; новые runs при записи этого статуса были queued, НЕ объявлять green. Отдельно зафиксированный CI на 2b7dcd3: focused Chrome, security, Docker и production image SUCCESS; Baseline Rails FAIL (RoomAiInstructionsSystemTest line 127, visible saved vs "Unsaved changes"; 170 runs, 2545 assertions, one failure). Новая разработка D5.1 ещё не получила зелёный CI. Исправлять конкретные assertions/состояния, не скрывать ошибку test helper. Не делать Railway, paid AI, новый DB schema.

**E2 — owner local AFTER verified CI:** При следующем обновлении pull только feature branch без сброса или checkout пользовательского M db/schema.rb. Пересобрать JS+CSS, restart web. В Project Circle нажать новую «Контекст AI» (вместо старого source edit в AI Plan): проверить popup, общий/Answer наследование, статистику, переключить M35 off, M33 on, Apply; при успехе inspect AI Plan показывает новый model target. Потом проверить «Вся история», режим автора, поиск и переключение на Finalizer — статус должен ясно говорить, что движок ещё не подключён. Прислать скриншоты popup, ошибок и status. Не платить и не запускать модель.

**E3 — дальнейшая очередь:** сначала закрыть CI + visual QA D5.1 и старый Baseline failure, затем server-backed named sets D5.2 (только после backup и db/schema diff), затем full-history retrieval D5.3, AI-filter gate D5.4 и интеграция 4 режимов D5.5. Отдельно D3: удаление других редакторов-дубликатов writing prefs/goal в AI Plan только с миграцией существующих UX тестов на canonical room settings.

## F. Обновление этого документа
Каждая следующая сессия обязана:
1. Прочитать current PR/HEAD/CI, сравнить с этим snapshot.
2. Обновить изменённые строки ID только доказательствами: `timestamp | ID | status | SHA | exact test runs | user QA | linked issue/PR | next gate`.
3. Делать **новый** commit `docs(status): checkpoint <ID> <result>` после кодовых изменений и проверять CI на новом HEAD. Если status stale — не считать старую отметку green.
4. Не менять прошлые `ACCEPTED` в `SPEC` без конкретной регрессии. Не переписывать master, если меняется только статус.

## G. Checkpoint 2026-11-21 — D5.1 single-entry source UI, snapshot BEFORE CI

**Новый нормативный ADR:** docs/ADR/2026-11-21_AI_CONTEXT_STUDIO_SINGLE_ENTRY_V1.md

**GitHub commits (branch PR #8, не main):**
- 00be967 — S8 privacy-scoped ContextMessages controller, source inventory; bfb181 / 3a74a2 — route and POST private search; dd0fec6 / b1b17a8 — controller tests with consent, DLP, scope, revoke.
- 9d0605b — ai_context_studio Stimulus single-modal selection; 0a28330 — canonical ERB UI; 35fffa8 — contextual Quiet Depth SCSS; d0d4dba — SCSS import; bcd7c2d — Stimulus registration; 913ea76/637a100/13d2349/a92d190 — RU/EN/ES/HY initial locales.
- f54bb02 — removed obsolete renderPlanSourceEditor and duplicate source cards from AI Plan; Answer bridge uses existing GenerationOrchestrator and signed SourceSelection. 3929b20 — updated Chrome source-selection acceptance tests.
- 41f84be / ec42cad — per-author counts, consent fingerprint, latest incoming and scoped avatar paths; f237162 / db11592 — JS apply fix, no unsafe localStorage reactivation after reload; 72ae9fa — reset default Answer revalidated by server; 5f3ee7c / c28ca65 — effective-vs-draft and target visible; 4a4ff63 — source UI states; 3c0f19c/c82d0f2/0a1efb4/d06bf29 — extended locales.
- d49d6df — single-source ADR; a status commit follows. **Exact HEAD must be read again.**

**Verified product facts vs limitations:**
- Full inventory UI uses ConversationCoverageSnapshotV2 (up to 10k eligible room messages), POST q/author/date paging 25 and DLP revalidation. Displayed content is not provider payload. No provider spends / sends in this endpoint.
- Current Answer is STILL capped at 240 most recent scanned candidates, 9 excerpts and 2400 chars; arbitrary older selection blocked, NOT full-history retrieval. Shared/current tool scope is an editable UI draft; other modes not wired. Saved sets are browser-local, no server CRUD or cross-device persistence. AI filter disabled pending approval.
- Owner-local db/schema.rb is modified and preserved. No migrations, Railway, merge, paid provider calls. **CI for latest D5.1 HEAD and manual browser verification pending.**
- Deprecated entrypoint in AI Plan source editor removed in code; other settings duplicate forms (goal/preferences) have NOT been removed; audit/staged D3 follows.
- Owner UI before D5.1 was only the supplied screenshot, not a visual acceptance of new changes. 

## H. D5.1 CI triage follow-up, 2026-11-21

**Predecessor d49d6df (not latest SHA):**
- Baseline Rails CI run 44914814101 — 664 runs / 10817 assertions / 1 failure. New context messages controller test line 39 submitted author_id as a JSON integer instead of browser-contract string; corrected test at 3710edc8258af8cdec13481138615a5108c01fb6.
- Focused Chrome run 44914814099 — 55 runs / 793 assertions / 3 failures. Old inspector test expected removed duplicate message bodies in AI Plan: corrected at 8ce81cb9638e0c4cc86b60599495cfb4c6bf42fc. Two new modal tests could not find message switches: discovered JS writing to reserved Stimulus Controller.scope getter. Renamed 22 occurrences to activeScope at 0658ef25190e232de247ee916e9869a9c13b5c48. Tightened Apply default server success at cc6c23b751d627601c7d1870aaf696c377fff836.
- Last CODE SHA before this status update: 8ce81cb9638e0c4cc86b60599495cfb4c6bf42fc. GitHub Actions on that SHA were queued/in_progress at last checked moment; fixes are NOT yet confirmed CI_GREEN or owner-accepted. After writing status, read new exact HEAD and Actions.
- Earlier legacy Baseline system failure RoomAiInstructionsSystemTest line 127 (at 2b7dcd3) remains separately tracked. Do not conflate with new controller test; do not erase legitimate saved instruction data.
- D5.1 stays IN_PROGRESS / CI_PENDING / OWNER_QA_PENDING until exact SHA CI + owner dark/light screenshot. Local modified db/schema.rb untouched.

## I. Owner Chrome screenshots + D5.2 implementation, 2026-11-21 (pending exact HEAD CI)

**Evidence from owner on 2026-11-21:** terminal output fast-forward 2b7dcd3 → c5ca0eb on feat/ai-answer-readiness-master-2026-11-20; yarn JS/CSS builds successful; docker compose restart web command completed. Git status still M db/schema.rb, untouched. Owner screenshots in Project Circle /rooms/3: full eligible count 11, select participant Jack → 6 filtered; manual switches, last incoming, independent Answer override, saved library disclosure, AI Plan, room settings, account default preferences. Critical owner findings: visual cards merged, no effective-config matrix or auto-saved snapshots, abrupt library accordion, service-level text chatter, source label M35 not human ordinal, redundant goal/style forms in AI Plan, and Plan-to-modal click dismissed Plan but did not open modal. This is **first visual feedback for D5.1**, not acceptance of D5.2.

**D5.2 code now on draft PR #8 (do not claim merged or owner accepted):**
- RoomAiContextMessagesController uses authorization-scoped participant_no/message_no from ordered eligible sources. Visible references P1.1, P2.6, original database source IDs preserved for ACL/server SourceSelection.
- Context Studio displays visually separated cards, active per-mode config board (shared + four functions), custom versus inherited state, selected count and participants, which mode is actually applied versus only local draft, short notes below each scope switch, four icon statistics, selected-vs-9/2400 model limit. All view-only search filters remain separate from source-altering author preset dropdown (both native-backed ui-select).
- Each Apply automatically snapshots scope and source rules in the browser's named-set library (room + mode + default/custom kind + affected person/count). Local drafts survive reload without being reactivated as server grants. Per-set accordion preview, Load and Delete; top library shortcut/count; nested smooth expand/reduce-motion.
- Opening Studio from expanded AI Plan now preserves pointerdown click and waits for Plan close motion; system regression added. Goal and writing settings forms removed from AI Plan and routed into the existing canonical room settings. Human-readable model task label and optional detailed explanation hide suggest_reply_for_human_review unless explicitly expanded. Duplicate raw purpose text no longer reprinted in AI Plan. Existing instruction revision controller and shared writing resolver kept.
- RU/EN/ES/HY locale strings and reduced-motion styles updated. Existing AI source review/evidence/H4/H5 flows are NOT blindly removed: runtime consolidation is still due in D3/D5.5. No new migrations, provider billing, send, Railway or main merge.

**Intermediate CI evidence (these are NOT exact latest HEAD results):** c5ca0eb: focused Chrome, security, Docker smoke, production image SUCCESS; Baseline Rails CI FAIL on 2 system cases (one Plan→Studio click + unrelated contextual preview). 1711136 focused Chrome CI ran 56 tests / 828 assertions / 3 fail, all due expected copy update or collapsed canonical instruction view; tests then corrected at e068d86. CI for subsequent commits is queued/running; ensure exact SHA success before acceptance. Known green 664 standard Rails tests at c5ca0eb do not supersede full-system failures.

**Next gated actions:**
1. Read PR #8 actual latest HEAD/actions, inspect any focused/Baseline failure job logs; patch only proven errors. Report exact SHA/test counts, never inherit earlier successful runs.
2. Owner after CI: pull feature, rebuild JS+CSS, check Studio top effective board/2 automatically saved variants, scope subtitles, icon stats, Pn.m, animated library, task details accordion, Plan→Studio direct click, and canonical settings navigation. No paid AI.
3. Before D5.3 server-backed named sets/migration, obtain backup evidence and inspect local dirty db/schema.rb WITHOUT discard; then implement cross-device persistent rules, full authorized history retrieval and provider provenance. Continue S8 AI-filter/four-mode integration only after independent gates.

## J. Hotfix 2026-11-21 — i18n::InvalidLocaleData blocks /rooms/3

**Owner evidence:** screenshot at local 20:50 21.11 shows Rails exception `I18n::InvalidLocaleData in Rooms#show`, Psych::SyntaxError on `config/locales/ai_context_studio.en.yml`, expected YAML key at line 4; URL `127.0.0.1:3000/rooms/3`. Owner pulled `c5ca0eb → fd3fb22`; `yarn build`, `yarn build:css` successful; Docker web restart completed. `git status --short`: only ` M db/schema.rb` before pull. **Regression introduced by our D5.2 locale edits, not PostgreSQL/CSS, no user fault.**

**Root cause verified via exact GitHub file contents:** all four `config/locales/ai_context_studio.{en,ru,es,hy}.yml` contained invalid concatenated mapping keys on the same line, e.g. `deleteSaved: "Delete"      usedCap: "..."`. YAML parser fails on the application locale load before rendering pages. Each locale was corrected in separate commits: en `75a0e777`, ru `21edf9b4`, es `44944505`, hy `f318521b`.

**Prevention:** `script/check_locale_syntax.rb` (commit `8a5a5f7`) uses standard-library Psych to syntax-parse **every** YAML locale file before Rails/I18n boot; fails with filename/exception if any malformed. New lightweight `.github/workflows/locale-integrity.yml` (`f2ec810`) validates locale syntax on PR and feature-branch pushes, without needing DB/frontend. `.github/workflows/ci.yml` (`46a3a02`) and `.github/workflows/ai-answer-focused.yml` (`3bcc1b8`) also invoke this fast fail gate before expensive jobs. CI on exact newest HEAD and owner reload not yet evidenced; mark `FIX_COMMITTED / QA_PENDING`, not full `ACCEPTED`.

**Owner next:** `git pull --ff-only origin feat/ai-answer-readiness-master-2026-11-20`; `docker compose exec -T web ruby script/check_locale_syntax.rb`; `docker compose restart web`, reopen `/rooms/3`. No yarn rebuild is needed for YAML-only fix; no migrations, no changes to dirty `db/schema.rb`, no paid model or Railway. If validator fails, collect exact lines and do not attempt to reset DB. Then continue D5.2 screenshot QA and fix remaining system CI failures separately.

## K. 2026-11-21 — D3.1 composer compact settings, first staged cut (CI/owner QA pending)

**Owner evidence:** screenshots /rooms/3 at 20:54–21:20 (after locale hotfix) show normal room and AI Plan rendering, Context Studio Shared default 11, AI Answer own override 9, then reapply all 11, 1–2 local named sets, and existing legacy large room/message settings and duplicate history diagnostics. Terminal owner confirmed `git pull de4d19f`, `Locale syntax OK: 77 YAML files`, Rails runner `I18n.t("ui.ai_context_studio.title", locale: :ru)` = `Контекст AI`. **Hotfix accepted locally; D5.2 accepted partially in one browser**, no paid model.

**Current design contract:** `docs/AI_MVP_IMPLEMENTATION_MASTER.md §11` (D3.1–D3.7), portable successor prompt `docs/AI_MVP_NEXT_CHAT_HANDOFF.md`. Exactly four visual entrypoints for now: Context AI (sole source editor), AI Plan (read-only), Message/Beautify (unsent draft editor), Room (canonical room prefs + instruction revisions + consent); a future AI Super Input is D3.7 LAST, not coded.

**D3.1 code changes on the draft PR #8 (not main; not owner-accepted):**
- `app/views/layouts/_new_message_form.html.erb`: unified four composer entrypoint classes; message/room inspectors now direct to their native task modals instead of retaining competing open popovers; old status target nodes remain for controller state but nested user control menu invisible; Plan explanatory boilerplate line removed. Room snapshot with redundant current profile/language/style hidden but underlying JS targets remain.
- `app/javascript/controllers/ai_draft_controller.js`: `openComposerEditor`, `openComposerRoom`; `openContextStudio` makes a **non-destructive** modal handoff without calling `finishClose` (which clears unsent working copy).
- `app/views/layouts/_new_message_form.html.erb`: separate legacy H3 source review/coverage/evidence and room-instruction one-shot duplicate sections hidden/inert in draft sheet; new visible direct `Контекст AI` link. Their backed controllers persist, NOT yet migrated to canonical resolver. **CRITICAL blocker:** visible H3 contextual task flow is not fully migrated; hiding legacy source review/one-shot can break old system tests and should NOT be shipped until the canonical flow is complete or a gated compatibility path exists. This is UI-retirement candidate, not final feature removal.
- `app/javascript/controllers/room_ai_instructions_controller.js` and ERB: always-visible inline room instruction name input (max 60) with existing `confirmName` reuse, title rename local templates only unless an explicit new content revision is saved; existing hidden edit controls retained for migration. Need verify blur/Enter/Escape / existing template and conflict safety tests.
- `app/assets/stylesheets/chat_compact_settings_d3.scss`: four same-style Signal Deck controls, compact Beautify/draft/room, room style presets, inline name, mobile/reduced-motion; imported at end of `application.bootstrap.scss`. Duplicate first-three draft preset buttons hidden, one full compact preset list remains.
- RU AI Plan `ready` reduced to `Готово`; no change to provider/ledger/send. Personal goal content still must be in canonical Room instructions only.
- `test/controllers/room_ai_context_messages_controller_test.rb`: predecessor CI `7d9efd2` Baseline failed only 1 Rails assertion of 664 tests / 10814 assertions: message list newest-first returned participant references [[2,1],[1,1]], test mistakenly required [[1,1],[2,1]]; sorted two ordinal pairs in test commit `b5b74bd`. This is an order-insensitive assertion fix, **NOT proof exact newest HEAD CI green**.

**Important NOT DONE:** D3.1 full system Chrome acceptance, legacy H3 test migration, source-review runtime consolidation, document preset panel integration, chat input AI mode. CI is queued/in_progress on intermediate commits; must inspect exact HEAD run before any owner pull. Local `db/schema.rb` remains modified but untouched by these changes, no migration. No Railway, no paid API, no merge or destructive cleanup.

**Next 1–3 engineering steps:** (1) check exact latest PR #8 HEAD CI; solve tests without weakening source/consent/no-spend guarantees and without breaking existing legacy contextual H3; (2) refine actual UX after owner screenshots of staged four entries, modal switch, inline name; (3) only when D3.1 green/owner accepted, continue D3.2/3.3 compact room/draft, then S8/Finalizer.

## L. 2026-11-21 — CI-led compatibility rollback + test updates (latest gate pending)

**Truth correction to K:** Initial D3.1 code temporarily hid the legacy H3 `.sd-ai-source-review` + one-shot room instruction in the draft; this **did break the old H3 feature flow**. Focused Chrome CI run 44936107588 on predecessor `524cba2` (not latest) reported 57 runs / 781 assertions, 3 failures+2 errors: hidden H3 source review in two tests; one hidden message/room indicator consent disclosure test; one hidden duplicate room snapshot assertion; one existing Pn.m test assumed fixed participant rank. Such failures are genuine regressions or stale visual assertions, NOT proof that Studio's backend is connected. **Fix:** at `8c6167c` restored the legacy source review and the room-instruction one-shot UX until full validated runtime migration. They remain visible *inside* the legacy advanced AI actions section, **not in the four composer primary buttons**. The duplicate source editing policy is still INCOMPLETE, to be removed only in D3.4 with proof.
- Source number test `316283a` asserts same user Pn.1/Pn.2 irrespective arbitrary participant rank.
- Room snapshot test `6e1aae6` now checks old controller targets still exist but are not visibly duplicated.
- Room instruction title tests `7c155f1` now exercise inline rename and local template reuse, rather than hidden pencil wizard.
- Composer control system test `708670f` now expects the Message trigger to open its modal rather than open a second popover.
- Legacy member-consent test `591cc40` now checks same protected consent metadata without relying on the removed inspector popover; exact member consent controls still in canonical Room settings.
- Baseline Rails CI predecessor `7d9efd2` failed 1 of 664 pure Rails cases due to ordering assumption in test `RoomAiContextMessagesControllerTest`; corrected independently in `b5b74bd` (sort ordinal pairs). No app data changed.
- Intermediate CI workflow runs contain other queued items; **the final HEAD after documentation must be queried for exact outcomes and owner must not pull yet**.
- Current D3.1 is `IN_PROGRESS / CI_PENDING / OWNER_QA_PENDING`. A narrower, visibly compact interface exists on feature branch; full user-facing elimination of legacy H3 source controls, dialog/document preset consolidation and AI Super Input remain NOT DONE.

## M. 2026-11-21 — D3.1 CI stabilization after first owner-requested compact UI slice

**Fixed predecessor check evidence** (exact old HEAD `e964dabd68e585c452243378419ce52fb986ce33`, *not* latest):
- `Locale YAML integrity` 44936657941 SUCCESS, `Security audit` 44936657862 SUCCESS, `Local Docker Compose smoke` 44936657881 SUCCESS, `Production image build (no deploy)` 44936657859 SUCCESS.
- Focused Chrome 44936657875 FAILURE: 57 runs / 846 assertions / 1 failure — named-set badge assertion used Selenium visible text for a **below-scrollport** counter. 
- Baseline Rails 44936657915 FAILURE: 664 unit/controller runs / 10821 assertions / 0 failures; separate full Chrome 172 runs / 2562 assertions / 4 failures: hidden room snapshot geometry, hidden duplicate quick presets, old room inspector disclosure after direct modal navigation, same Context Studio counter.
- Main owner safety invariants remain: source ACL/consent/signed bounded selection, existing H3 source review restored as a compatibility screen, no provider/Send, no migration, no `db/schema.rb` manipulation.

**New exact code changes (on feature branch; not merged):**
1. `42bb4b1`: geometry system test measures actual canonical visible Room settings instead of intentionally removed duplicate snapshot; responsive containment remains asserted.
2. `2befaa8`: one compact six-style picker system test; all six options remain verified, own unsent message/Send count still asserted.
3. `2f43ab5`: incoming translation display mode test confirms Room entry opens canonical dialog without an extra popup; existing language/translation assertions remain.
4. `ffc1c4f`: added explicit DOM/localStorage diagnostics to Context Studio autosave Chrome test. On its focused Chrome CI run 44944923879 the `assert_equal "1", saved_state.fetch("countText")` **PASSED**, while subsequent Capybara visible-text assertion for the offscreen lower badge failed. This is a test visibility/scroll issue, **not evidence of failure to save**. Same run: 57 runs / 839 assertions / 2 failures (one intermittent Plan close→Context open).
5. `2d65b47`: badge assertions now use the **visible upper shortcut `data-count`** and DOM `textContent`, preserving verification of actual named-set count instead of Selenium's clipped element text.
6. `63d17d0`: `ai_context_studio_controller.js#open` now waits for an in-progress AI Plan *close* animation even when `planOpen` is already false, with 280ms bounded fallback. No change to signed source validation or AI spend.

**CI on the last CODE HEAD `63d17d0`:** Locale YAML integrity and Security audit had succeeded on immediate inspection; Baseline Chrome, focused Chrome, Docker smoke, production image were in progress. **This is NOT CI_GREEN and NOT owner QA accepted.** Before any owner pull, re-check latest PR #8 head SHA and *all six* workflow conclusions, inspect any failures and fix actual cause. A doc-only update to this status creates a new branch HEAD; do not mistake earlier code-run success for exact doc-HEAD acceptance.

**Pending:** D3.1 exact-head CI pass + first owner Chrome dark/light/mobile screenshot. H3 advanced source-review duplicate remains intentionally active until D3.4 validated server-side selection adapter; D3.2 slim Beautify and D3.3 room presets remain NOT STARTED. D3.7 AI Super Input is planned LAST.

**Next 1–3:** (1) resolve exact newest CI; (2) owner fast-forward feature branch *without* changing modified local `db/schema.rb`, yarn JS/CSS build/restart and four-entry UI acceptance, including clicking Context immediately after closing Plan, inline naming, no lost drafts; (3) only after acceptance, D3.2/3.3 and test-driven removal of legacy source UX.

## N. 2026-11-21 — D3.1 saved-set library browser regression: viewport, not lost data

**Additional exact CI (old code HEADs):**
- Focused run 44945193511 at `2d65b47`: 57 tests / 856 assertions / 1 failure at `ai_answer_entry_quiet_depth_system_test.rb:406`. The modal library was expanded and two saved entries were in the DOM, but `assert_selector ... count:2` with Selenium's default visible setting could not detect the rows below the modal scroll viewport. Previous checks verified upper badge count and DOM counter text. **No proof of source loss.**
- Focused run 44945228981 at `63d17d0`: 57 tests / 851 assertions / 2 failures: same below-scrollport saved entries plus a flaky *legacy H3* explicit Client Brief result assertion on `Editable working copy` (test/system/ai_contextual_reply_system_test.rb:620), which passed in adjacent runs. Its root cause is not yet established; do NOT silently disable or remove H3 tests.
- Focused run 44945456166 at `3b6bd5f`: 57 tests / 858 assertions / 0 failures / 1 error: after opening the saved-set library at the bottom of a scrollable modal, the test tried to click the header close button above the viewport and could not find it as visible. Both saved-set cards were counted in DOM successfully.
- `3b6bd5f` changed the library-entry count assertion to `visible: :all`, while retaining the library-open and two-record count assertions. `c7592cc` changed closing from an offscreen header click to accessible **Escape** followed by verification that the native dialog closed; it then still reloads and checks snapshots remain browser-local/inactive until reapplication.

**Latest code commit for this checkpoint:** `c7592cc70f2472df4f044b60f671685b1ccc709c`, tracked under PR #8. Latest code-run Locale YAML integrity and Security audit had SUCCESS; full Chrome, Baseline Rails, Docker smoke and production image were running/queued when checked. Update after final job conclusions before any user pull. A pending CI is **not** ACCEPTED. Existing H3 historical source preview still runs under its own legacy advanced panel; D3.4 canonical integration is NOT implemented. No user DB changes, paid AI, sends, Railway or main merge.

**Next:** check exact newest workflow runs, inspect any reproducible H3 stale-result/scroll issues rather than masking errors; only after green verify owner /rooms/3 four primary buttons, stable Plan→Context, inline instruction title, legacy advanced H3, full private ACL/draft retention and light/dark responsive.

## O. 2026-11-21 — D3.1 focused Chrome green on code SHA, independent close-transition test stabilization

**Verified code SHA `c7592cc70f2472df4f044b60f671685b1ccc709c`:**
- Focused Chrome GitHub Action 44945772548 **SUCCESS**, exactly **57 runs / 863 assertions / 0 failures / 0 errors / 0 skips**. This validates bounded-Answer, Context Studio saved-set selection, room instruction, composer and legacy H3 subset on this SHA. This is NOT whole-system CI or owner browser acceptance.
- Security audit 44945772584 **SUCCESS**, Locale YAML 44945772754 **SUCCESS**, Local Docker Compose smoke 44945772567 **SUCCESS**, Production image build 44945772569 **SUCCESS**.
- Baseline Rails 44945772564 had not finished at time of this status update.

**Document HEAD `2f51fcc7` (identical code, refreshed status):** focused Chrome 44945877036 **FAILED**, 57 runs / 855 assertions / 1 failure. The affected test `AiAnswerEntryQuietDepthSystemTest#test_Context_Studio_is_the_only_source_editor...` toggled AI Plan closed and immediately clicked Context Studio during the Plan's ongoing 195ms exit animation. Its purpose is canonical source-editor exclusivity; the *separate* case `clicking Context Studio while AI Plan is open...` already covers the actual direct handoff and passed. `95553d2` explicitly waits for `[hidden][data-motion='closed']` before the unrelated source-editor assertion. The application still has a bounded Plan-animation wait in Context open; exact latest CI and owner rapid-click QA remain pending.

**Current code commits after previous checkpoint:** `95553d2` test-only synchronization; no schema, provider, billing, consent, auto-send, production deploy or migration changes. All previous H3 controls are preserved until proper server runtime consolidation. No falsely claimed complete S8/Finalizer.

**Gate:** D3.1 remains `IN_PROGRESS / CI_PENDING / OWNER_QA_PENDING` until all six exact HEAD workflows pass and owner sends Chrome screenshots. Check latest PR #8 HEAD and CI again after the status commit; never quote the earlier green code SHA as proof that a later HEAD is green. Then D3.2 (slim Beautify) and D3.3 (room settings) can proceed.

## P. 2026-11-21 — D3.1 inline instruction title regression; current CI gate

**New fact from exact full Baseline run 44945772564 at CODE SHA `c7592cc`:**
- 664 Rails tests / 10821 assertions / 0 failures; Redis throttle+ActionCable standalone smoke 2/6 and 1/5 pass;
- 172 full Chrome tests / 2578 assertions / **2 failures**, no errors:
  1. `RoomAiInstructionsSystemTest#test_renamed_room_revision_becomes_a_reusable_template_in_another_room_with_explicit_Save` at line 191: inline title unexpectedly became `Instruction #1Project scope rules` instead of exact user text. This was a **real input handling bug**, not a stale assertion. The `change` event ran while Capybara cleared/retyped the input, causing the default name to be reinserted. Patched in `151781538f5e7f0de3f3166d2b8c8df1297d96df` (commit only on **blur**, not intermediate change) and `3049119c7811f01df1ef34c273aedd25b7318fb7` (Enter triggers one blur/commit; explicit `confirmName(event = null)` so no implicit browser global; avoid stealing focus). **Exact post-fix CI unverified at time of writing.**
  2. `AiEditorClaritySystemTest#test_room_settings_show_consistent_icon_sections_and_a_responsive_six-column_style_grid` at line 170: clicking native translation `<summary>` did not yield `details[open]` in that run, though other tests and earlier Baseline run 44945877035 on DOCS-ONLY SHA `2f51fcc7` passed 664 Rails / 10821 assertions **and** full Chrome 172 runs / 2601 assertions / zero failures. Currently classified `INTERMITTENT / NEEDS REPRO`, not casually bypassed; no source code change for native `<details>`.

**Focused Chrome:** code SHA `c7592cc` run 44945772548 PASS 57 runs/863 assertions/0 failures; later docs SHA `2f51fcc7` focused 44945877036 had 1 transition-race test failure (manual rapid Plan-close→Context open without waiting). `95553d2e2246cf2eaac4651644d8e1c2b62c09fa` stabilized unrelated source-editor test by awaiting `[hidden][data-motion='closed']`; separate direct handoff test retained. 

**Current code HEAD `3049119`**: Security audit 44946282851, Locale YAML integrity 44946282835 and Docker smoke 44946282839 SUCCESS; focused Chrome 44946282921, full Baseline 44946282940 and Production image 44946282837 in progress at last check. After this docs checkpoint actual newest branch HEAD changes: recheck exact PR #8 HEAD/runs. Do not claim all-green/owner-accepted based on older SHA. No DB change, no paid provider/Send/merge/deploy.

**Next gate:** finish exact-head CI; if full system still reports translation fold flakiness, inspect real click/focus and native details semantics without weakening checks. Owner's updated D3.1 visual acceptance will then test direct four-entry toolbar, inline name, Context/Plan, and unsent draft retention. D3.2/3.3 not started until validated.
