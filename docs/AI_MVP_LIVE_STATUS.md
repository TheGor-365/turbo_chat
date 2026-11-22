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

## Q. 2026-11-21 — D3.1 title editor: intermittent duplicate auto-name after earlier CI green

**Evidence requiring correction of previous acceptance:** Code `3049119` full Baseline CI 44946282940 SUCCESS: 664 Rails / 10821 assertions plus 172 full Chrome / 2602 assertions, 0 failures; focused 44946282921 SUCCESS 57/864; Security/Docker/YAML/image all SUCCESS. Yet latest *documentation-only* commit `8bf1dff` Baseline 44946496858 FAILED: 664 Rails / 10821 assertions / 0 failures, 172 Chrome / 2586 assertions / **one failure** in `RoomAiInstructionsSystemTest` at line 191. Actual inline-name input was `Instruction #1Project scope rules`, not user-entered `Project scope rules`. Source code identical; this reveals a **flaky real UI input timing bug**, not safe to accept based on one green run. All other doc-HEAD checks SUCCESS: focused 44946496875, locale 44946496987, security 44946496856, docker smoke 44946496903, production image 44946496944.

**Root hazard:** asynchronous Stimulus `renderDraftName()` can reapply a default label during an active inline-title edit, and focusing an existing name without selecting can append typed characters. **New code:**
- `4b2aa125a09f985418a69bb1278215014189dc58` introduces `editingInlineName` guard, `inlineNameFocus` selects the full initial name, guards all programmatic value updates while editing, `inlineNameCommit` captures the exact typed text at blur and writes it through existing template/name validation; no new revision or message on rename.
- `3698bed2cc415b256a7696c93dc30bb2f4dcaad9` wires Stimulus focus to select initial name; blur/Enter single commit remains.

**As of this status update:** focused Chrome 44947160460, full Baseline 44947160489 and Docker/image on `3698bed2` pending; Security 44947160452 and YAML 44947160470 SUCCESS. Do not mark D3.1 `ACCEPTED` until repeat full Chrome is green *and* owner tests renaming in local Chrome. App code does not alter existing room instruction revisions, ACL/consent, send, paid provider, migrations, Railway or modified local `db/schema.rb`.

**Next:** inspect exact CI after documentation change; if title still concatenates, replace the default title as *placeholder* until first user save and add an explicit focus/typing browser regression. Check that previously saved custom titles still render without loss. Continue D3.2 only after this gate.

## R. 2026-11-21 — D3.1 reproducible auto-title overwrite: default as placeholder (owner QA pending)

**Evidence at former exact HEAD `a8b4f3b50ccd8874acc04f6c5a5a4305b8044a86`:** locale, security, Docker smoke, focused Chrome and production image SUCCESS. Baseline Rails CI run 44947218785 completed FAILURE: pure Rails **664 runs / 10821 assertions / 0 failures**, Redis throttle and cable integration pass; full Chrome **172 runs / 2581 assertions / 2 failures**. Confirmed failing UI test `RoomAiInstructionsSystemTest` line 191: generated default name was concatenated with a human edit (`Instruction #1Project scope rules`) despite prior guard/select-on-focus. A separate `MessageRevisionRecoverySystemTest` reaction HTTP-sync test failed at line 79 once; this belongs to realtime recovery, **no demonstrated causal connection** to D3.1 rename and not suppressed. Adjacent earlier runs had passed it; treat as **NEEDS_REPRO**, not automatically a nonissue.

**Fix to eliminate structural overwrite rather than adding sleeps:** 
- `3a613417acd2e13c202c4ebc8c76c39f47520bc2` in `room_ai_instructions_controller.js`: an auto-generated title is represented as placeholder, not the input's editable value; updates to the controller do not reinsert default during async re-renders or Selenium/native field clearing. Explicit user names remain editable. Existing validation, append-only revision saves, template library and no-Send boundaries unchanged.
- `cee6065c2d4bcca085110688253f0d709316eacf` in `_new_message_form.html.erb`: empty editable name field with localized default name placeholder.
- `86caa795c0e52f49b39d307da82d65386c6d88ca` in `room_ai_instructions_system_test.rb`: asserts initial blank input, default title placeholder, exact typed value before and after blur, then real saved revision and cross-room template reuse with unchanged unsent chat.
- D3.2 read-only code audit: `_new_message_form.html.erb` has six style buttons in draft editor, working text, comparison/preview, explicit Apply/Undo, legacy H3 source-review/task controls; D3.2 may slim presentation but cannot hide legacy source review before canonical D3.4 runtime migration.

**CI at last CODE SHA `86caa795` at time of writing:** Locale integrity 44947865267 SUCCESS, Security audit 44947865323 SUCCESS, Docker smoke 44947865243 SUCCESS, Production image 44947865285 SUCCESS, Focused Chrome 44947865270 **SUCCESS: 57 runs / 864 assertions / 0 failures / 0 errors**; full Baseline 44947865282 **IN_PROGRESS**, not accepted. Writing this status changes branch HEAD: verify exact subsequent HEAD workflows before owner pull. No migration, main merge, provider spend, auto-send, Railway, local db/schema.rb reset or rewrite.

**Gate / next:** 
1. Inspect exact-HEAD Baseline conclusion, regressions and retry without weakening assertion if it fails; keep reaction-sync issue separate.
2. Owner after full green: safe fast-forward feature branch preserving dirty `db/schema.rb`, build JS/CSS and restart web; verify 4 primary entrypoints, direct Plan→Context handoff, manual instruction name **overwrites**, not appends, with existing unsent human draft intact; dark/light/compact screenshot.
3. Only then D3.2 compact Beautify (manual draft + preview/apply/undo + attachments, H3 compatibility) and D3.3 room presets. S8 shared server context, Finalizer and AI Super Input remain gated and not claimed implemented.

**Status: D3.1 `CI_PENDING / OWNER_QA_PENDING`; D3.2 `AUDITED_NOT_IMPLEMENTED`; D3.3 `NOT_STARTED`.**

## S. 2026-11-21 — D3.1 post-fix CODE CI_GREEN; owner acceptance gate

**Authoritative green code commit `86caa795c0e52f49b39d307da82d65386c6d88ca`:** GitHub Actions:
- `Baseline Rails CI` run **44947865282 SUCCESS**, pure Rails **664 runs / 10821 assertions / 0 failures / 0 errors / 3 skips**, Redis throttle **2 runs / 6 assertions / 0 failures**, Redis ActionCable process **1 run / 5 assertions / 0 failures**, complete Chrome **172 runs / 2605 assertions / 0 failures / 0 errors / 0 skips**. This covers the previously flaky inline-title editor and the reaction HTTP-sync test on this exact code revision.
- `AI Answer / Quiet Depth focused Chrome CI` run **44947865270 SUCCESS**, **57 runs / 864 assertions / 0 failures / 0 errors / 0 skips**.
- `Security audit` 44947865323 SUCCESS, `Locale YAML integrity` 44947865267 SUCCESS, `Local Docker Compose smoke` 44947865243 SUCCESS, `Production image build (no deploy)` 44947865285 SUCCESS.
- A **status-doc-only** HEAD `36c481a05015b2968ca867e89630c3e8be0e8295` then triggered new Actions. Locale and Security had passed; full Baseline/focused/Docker/image were still in progress at last check. This section itself is another doc-only commit; confirm exact newest HEAD before stating final CI green. **No production deploy.**

**D3.1 engineering change set now CI_GREEN at code SHA:** four primary composer controls, no duplicate summary popovers, direct Message/Room editors; bounded Plan→Context handoff; Consent/ACL and source-editor safety; legacy H3 compatibility restored; inline title uses generated placeholder rather than polluted editable text, and exact custom title saved without creating another room revision; original unsent human draft unchanged.

**Status classification:** D3.1 `CODE_CI_GREEN / OWNER_QA_PENDING` (not yet `ACCEPTED`). D3.2 `AUDITED_NOT_IMPLEMENTED`; D3.3 `NOT_STARTED`; D3.4 shared server selection and D3.7 AI Super Input remain unimplemented. React HTTP-sync intermittent failure was seen in previous exact run but passed in final code run; continue to monitor, never suppress the test. Browser-local saved context sets are not cross-device; Answer bounded sources still 240/9/2400; no paid AI.

**Owner QA after latest PR HEAD tests:** 
1. From existing feature branch use `git status --short` then `git pull --ff-only origin feat/ai-answer-readiness-master-2026-11-20`, do not discard or reset dirty `db/schema.rb`. If pull refuses to fast-forward, stop and show error, do not stash/reset automatically.
2. Rebuild from Docker `docker compose exec -T web yarn build && docker compose exec -T web yarn build:css && docker compose restart web`, inspect `/rooms/3` (or existing private Project Circle) without paid AI.
3. Screenshot four equal toolbar actions and the instruction-title field with placeholder `Instruction #N`; type `Project scope rules`, Tab, confirm no concatenation, navigate Plan→Context and back, ensure ordinary chat draft remains unsent. Test dark/light and compact if feasible. Once user supplies evidence, mark `ACCEPTED` and then implement D3.2 slim draft in a separate bounded step.

**Artifacts:** [PR #8](https://github.com/TheGor-365/turbo_chat/pull/8), [source master](https://github.com/TheGor-365/turbo_chat/blob/feat/ai-answer-readiness-master-2026-11-20/docs/AI_MVP_IMPLEMENTATION_MASTER.md), [handoff](https://github.com/TheGor-365/turbo_chat/blob/feat/ai-answer-readiness-master-2026-11-20/docs/AI_MVP_NEXT_CHAT_HANDOFF.md). Do not claim this content appeared in another chat or Drive automatically.

## T. 2026-11-21 — Corepack registry-rate-limit CI hardening; D3.1 owner acceptance remains pending

**After CODE_CI_GREEN at `86caa795` (see §S), docs-only HEAD `78aef021` introduced no functional code changes, but focused workflow 44948351178 FAILED before Rails/Chrome because Corepack requested `https://registry.npmjs.org/yarn/latest` and npm registry returned **HTTP 429**. This was a CI package-manager bootstrap failure, NOT evidence of failing Rails behavior. Do not relabel the green code regression suites as failed product logic.

**Verified repository compatibility:** existing `yarn.lock` is Yarn Classic v1, and `Dockerfile` already explicitly installs `yarn@1.22.22`. `package.json` previously lacked `packageManager`, so Corepack could request unpinned latest metadata.

**Fixes committed on draft PR #8 (no database/provider changes):**
- `9e92c8933459a228755aa53b94e8b5a563185c2c` — add `"packageManager": "yarn@1.22.22"` to package.json, no package dependency bump.
- `ed0975b1460e058b6103b596d752817a4589bd2e` — focused Chrome workflow explicitly sets `COREPACK_DEFAULT_TO_LATEST=0` and checks `yarn --version == 1.22.22` before asset install.
- `1b0ac6538d78d4cde935b37c5994b9bfc85249fe` — identical guard on full Baseline Rails workflow.

**Exact CODE SHA `1b0ac653` observed results before writing this checkpoint:**
- `Security audit` 44948534955 SUCCESS;
- `Locale YAML integrity` 44948534935 SUCCESS;
- `Local Docker Compose smoke` 44948534913 SUCCESS;
- `Production image build (no deploy)` 44948535015 SUCCESS;
- `AI Answer / Quiet Depth focused Chrome CI` 44948534928 SUCCESS; new pinned-Yarn bootstrap and Chrome both passed;
- `Baseline Rails CI` 44948534929 **IN_PROGRESS** (frontend asset bootstrap completed successfully, no Yarn registry latest failure observed).
The new status-doc-only commit itself changes the exact branch HEAD; re-check its own Actions before owner acceptance. Do NOT invent a completed Baseline on `1b0ac653` if it has not actually completed.

**Gate:** D3.1 `CODE_CI_GREEN at 86caa795 / PINNED_YARN_CI_IN_PROGRESS at 1b0ac653 / OWNER_QA_PENDING`; D3.2 `AUDITED_NOT_IMPLEMENTED`, D3.3 `NOT_STARTED`. PR #8 remains draft. Local dirty `db/schema.rb` is not touched; no production deploy, no paid AI, no Send, no migrations.

**Next 1–3:** Check exact-head Baseline; if green, owner safe ff-only pull/build/restart, screenshot four buttons and inline name (default placeholder then custom title), verify draft retained and no paid model; after visual QA, begin D3.2 compact Beautify without deleting legacy H3 source review until D3.4.

## U. 2026-11-22 — Owner review at local 3c7e784; six-state composer hub + dedicated instructions (D3.1a)

**User-authenticated local facts from command output/screenshots:** Linux feature branch `feat/ai-answer-readiness-master-2026-11-20`; `git pull --ff-only` from `de4d19f` to `3c7e784` SUCCESS; JS build 850.9KB and CSS Sass completed; docker compose db healthy/Redis up/web restarting then up; ` M db/schema.rb` was preserved. Screenshot `/rooms/3` shows four equal primary buttons, room with old history, Plan panel open; owner explicitly says `План AI ↔ Контекст AI` transitions work. **No screenshot proved draft sentinel retention, mobile behaviour, instructions save, or paid AI execution**, so do not mark those accepted.

**Owner UX objections (verified from screenshot vs exact branch UI):** room statuses were hidden in legacy inspector markup by `chat_compact_settings_d3.scss` (missing color/on/off at-a-glance). Room and Message dialogs remained visually distinct from Plan, instructions buried in Room. Owner asks green on/red off indicators, smooth toggle and sheets, separate Instructions button, no new reload, one canonical owner, realistic synthetic test dialogue, future removal of redundant old sub-navigation. The original stage D3.1 is **PARTIAL OWNER QA** rather than fully accepted.

**D3.1a code implemented on PR #8, feature branch only:**
- `55e62d3`: new `composer_settings_hub_controller.js` reads existing DOM/permission controllers, does not store settings or PATCH directly; reversible switches call canonical handlers; consent opens canonical Room instead of silently granting permission.
- `170c5b4`: Stimulus registration; `fa21cc1`: status strip + Instructions button in composer; 4 locale files RU/EN/ES/HY `2f64f76`, `29bf918`, `44d9b03`, `6cbfcaa`, subsequent corrected scope labels.
- `ee2fe6f`: separate Instructions entry filters **same** room instruction editor/revision and local named templates, no duplicated model/form; `68e822b` localized panel title.
- `4ebc5c7`, `68b746a`: green check/red X/amber pending, status row separated from actions, native Room and Message dialogs styled as bottom Plan-shaped sheets with smooth open/close, reduced-motion and mobile fallbacks; legacy settings content remains live, not duplicated.
- `77112e8`, `63a4826`: add status `room history eligible` distinct from own consent, scoped tooltip and six indicators. Corrected property mapping of input `role=switch` in `7cabfee`, so local translation checkbox uses actual `.checked` rather than absent `aria-checked`.
- `61772c2`, `69f84c2`: opening the Message/Room/Instructions sheet closes Plan and restores focus to triggering control; no page reload or provider call.
- `27b6637`: new Chrome acceptance tests verify six indicators, reversible spelling, standalone instruction editor and consent's deliberate grant safety. **CI results pending**, cannot claim passing or owner accepted.
- `8046578`: 14-message synthetic Jack/Eric story for semantic/ACL/422/price-vs-approval/source-selection/poisoned-instruction checks. `69f7e5d`: master §12 records detailed state taxonomy, plan-like UI and deliberately unfinished transition to D3.2/D3.3.
- Current code still keeps legacy H3 source review and old Room↔Message in-dialog navigation for compatibility; those legacy panels are **NOT emptied**. This was intentional to avoid breaking existing H3 acceptance and needs separate staged migration/test. AI Super Input and Finalizer remain planned, not implemented.

**Base-branch CI before this slice:** code `1b0ac653` six workflows SUCCESS; local `3c7e784` five success, Baseline run 44949197197 FAILURE: pure Rails 664/10821 success, full Chrome 172/2582 one failure in `AiContextualReplySystemTest#test_structured_preview_is_inert,_editable,_copyable_and_exportable_without_sending` (Generate with Grok button disabled at line 469). Could be H3 timing; do not silently suppress. New D3.1a exact-HEAD CI currently queued/running, plus previous H3 failure may recur.

**Checked status:** D3.1 `OWNER_QA_PARTIAL`; D3.1a `CODE_COMMITTED / CI_PENDING / OWNER_QA_PENDING`; D3.2 `NOT_STARTED`; D3.3 `NOT_STARTED`; D3.4 `NOT_IMPLEMENTED`. No migrations, paid AI, Send, main merge, Railway, local schema reset.

**Next 1–3:** (1) inspect exact latest PR HEAD workflows, fix any real system regression; (2) user safe fast-forward/build/restart only after CI guidance, screenshot six visible chips and Instructions bottom sheet, toggle Spelling/Details and observe green/red without reload, create QA room (not Project Circle) for version-save test; (3) run synthetic dialogue review and stage D3.2 once P0/P1 defects removed. Each observation logged PASS/FAIL/PARTIAL and severity in master status. [Browser runbook](QA_D3_1_OWNER_BROWSER_ACCEPTANCE_2026-11-21.md) and [semantic QA data](QA_SEMANTIC_DIALOGUE_AI_PIPELINE_2026-11-22.md).

## V. 2026-11-22 — P0 template 500 fixed; exact CI advanced to two-browser gates; scoped toggle audit

**Regression found by automated full CI during D3.1a**: Pre-fix head `69f7e5db` Baseline 44951350106 reported widespread HTTP 500 on any authorized room view. This was NOT dozens of independent failures: new status markup passed icon names `activity`, `check-circle`, `x-circle` to `sd_icon`, while `SignalDeckHelper::ICONS` is a whitelist of 56 keys and rejects unknown names with `ArgumentError`. This was a **real P0 room rendering defect in feature branch**, never deployed locally or to production. `ba75197d0a3191a42eabce3d8eaeecfaef0e9f43` replaces the three with whitelisted `sliders-horizontal`, `check`, `x`. Colored on/off semantics remain in CSS. Do not add arbitrary Lucide names without checking this helper.

**Related small correctness fix** `181cfbfb4112c5d1691788cdf87679147b03c52e`: unknown room-history readiness stays amber `pending` until server status arrives; failed consent lookup shows unavailable instead of misreporting false/off. `53fc9987b64ca577834b1c73d2e8eac0d8b17e29`: clicking own-grant/eligibility/auto badge opens Room scrolled to the actual consent or locked-auto control, not a hidden authorization action; focus returns to the invoking status badge.

**Live UI/architecture inventory** `docs/SETTINGS_STATUS_INVENTORY_2026-11-22.md`: exactly **five original room controls** (spell, own grant, locked auto, local translation, detailed view) and **one derived** eligible-history state = six visible badges. In the composer two additional guarded *one-shot* toggles `roomInstructionToggle` and `briefSpendConsent` must NOT become persistent direct actions. The navbar's theme is tri-state, room mute server-backed, and per-message Context Studio toggles dynamic (cannot invent a universal fixed count). New badges do not own preferences. `docs/QA_D3_1A_STATUS_AND_INSTRUCTIONS_2026-11-22.md` provides manual checks for live toggles, independent Instructions sheet and browser ergonomics; synthetic semantic QA is in separate 14-message fixture document. Actual user tests for this new release **NOT PERFORMED**.

**Gate evidence while authoring:** On CODE SHA `ba75197d`, `Locale YAML integrity` 44951643712 SUCCESS, `Security audit` 44951643738 SUCCESS, Docker smoke 44951643709 SUCCESS; full Baseline 44951643716 had advanced from Rails/unit and Chrome to **Two-browser realtime system acceptance (real Redis adapter)**, but was still `IN_PROGRESS` (not yet all green). Other workflow runs and exact newest docs HEAD queued/in progress. Do not cite completed 664/175 counts until logs/CI conclude. Code after this commit includes a tiny readiness indicator change and a consent-button focus correction, whose exact CI also pending. **Status: D3.1a `CODE_COMMITTED / CI_PENDING / OWNER_QA_PENDING`, NOT ACCEPTED.**

**Known incomplete:** legacy H3 source controls and cross navigation within the old Message/Room modals remain. New CSS makes those native dialogs Plan-shaped, but does NOT empty/remove their actual internal forms; they must be migrated with tests in D3.2/D3.3, and global source selection backend is not shared until D3.4. The new dedicated Instructions button owns a separate view of the *same* revision editor. No main merge, Railway, paid provider call, automatic Send, schema change or migration.

**Next 1–3:** (1) inspect latest exact feature HEAD CI; regressions from new System `ComposerSettingsHubSystemTest` must be fixed rather than bypassed; (2) only when CI acceptable ask user to safe pull/build/restart preserving dirty `db/schema.rb`, then first screenshots of six-state bar before/after Spelling and dedicated Instructions room; (3) track owner PASS/PARTIAL/FAIL + P0/P1/P2 and proceed to D3.2 once safe. 


## W. 2026-11-22 — D3.1a CI repair at code SHA 88e6138; owner acceptance still pending

**Read from GitHub Actions, exact previous HEAD `f32c7545b9ed2b3ab1d49c318f3ccb499bffe922`:** five workflows SUCCESS (locale syntax, security, focused Chrome, Docker smoke and production image without deploy). Baseline Rails CI run [44951906533](https://github.com/TheGor-365/turbo_chat/actions/runs/44951906533) FAILED: pure Rails **664 runs / 10821 assertions / 0 failures / 0 errors / 3 skips**, separate Redis throttle and ActionCable checks PASS; full Chrome **175 runs / 2393 assertions / 1 failure / 14 errors**. These failures are NOT an accepted implementation.

**Proven defects, not papered-over tests:**
- All four new `config/locales/composer_settings_hub.{en,ru,es,hy}.yml` defined YAML keys `on:` / `off:` unquoted. YAML's boolean-key coercion made `ui.composer_hub.on/off` missing; in HTML `data-on/off` this produced `translation_missing` markup and damaged pill attributes, correlating with multiple Selenium `ElementClickInterceptedError` failures. Plain YAML syntax CI did not catch this semantic key error.
- `chat_composer_status_hub.scss` had `position:sticky` on native dialog topbars, contrary to existing `AiEditorClaritySystemTest` contract requiring nonsticky scrollable panels. Full Chrome reported `Expected "static", Actual "sticky"`.
- The duplicate-key PostgreSQL diagnostics printed during Rails system tests are not by themselves proof of unhandled production database errors; distinguish them from explicit test failures.

**Fix on feature branch only:** atomic commit [`88e613809d9969b040664745773fb89ff95e0ff2`](https://github.com/TheGor-365/turbo_chat/commit/88e613809d9969b040664745773fb89ff95e0ff2): quote `"on"` and `"off"` locale keys in RU/EN/ES/HY, restore `position:static` on both dialog topbars, add `ComposerSettingsHubSystemTest` regression requiring eight translated on/off strings and plain DOM `data-on='On'`/`data-off='Off'`. No test removed or security requirement weakened.

**Verification at time of this status edit:** GitHub readback confirmed updated locale and new regression; on `88e6138` Locale YAML integrity run 44952860411 SUCCESS, Security 44952860440 SUCCESS, Focused Chrome 44952860419 SUCCESS, Docker smoke 44952860415 SUCCESS, Production image build 44952860425 SUCCESS; **Baseline Rails CI 44952860408 IN_PROGRESS** in the full two-browser step. Therefore `D3.1a FIX_COMMITTED / EXACT_HEAD_BASELINE_PENDING / OWNER_QA_PENDING`, not green or accepted. Writing this section advances HEAD again; inspect its own six workflows.

**Drive checkpoint:** Existing private `07_TURBO_CHAT/TURBO_CHAT_README_INDEX_2026-11-03` updated with an explicit 2026-11-22 superseding engineering entry and connector readback, URL: https://docs.google.com/document/d/1KkhXqi7eWXF89IwP4pta5vOEIepuBlOYziSVwmDt2as/edit . No new Drive folder or exposed credentials.

**Next, gated:** (1) inspect exact newest feature HEAD six CI checks and any remaining real Chrome failure, repair code instead of disabling tests; (2) after acceptable checks, owner safely fast-forward/rebuild/restart preserving ` M db/schema.rb`, test six state badges and dedicated Instructions sheet on `/rooms/3` without Send/model; (3) classify dark/light + 390px Plan→Message/Room browser QA before D3.2. No DB migration, main merge, Railway, paid AI, context-grant toggle without consent or automatic Send.


## X. 2026-11-22 — D3.1a exact CODE SHA CI GREEN; manual browser acceptance next

**Root cause follow-up from the first fix (`88e6138`):** on exact code SHA `88e613809d9969b040664745773fb89ff95e0ff2`, all five other workflows SUCCESS, but Baseline Rails CI 44952860408 FAILED: Rails 664/10821 PASS; full Chrome **176 runs / 2480 assertions / 0 failures / 10 errors**. All 10 Selenium `ElementClickInterceptedError` reports selected the **consent status chip** when tests asked for `click_button "Room settings"`: the consent `title` contained the same English substring `Room settings`. Although missing I18n and sticky topbar were resolved, this ambiguous accessible locator remained a real UX/test selector regression, NOT a test to skip.

**Correction:** [`edfd8685b759369ec60a0bb4e006d24b3b54553d`](https://github.com/TheGor-365/turbo_chat/commit/edfd8685b759369ec60a0bb4e006d24b3b54553d) changes only the English `composer_hub.consentHelp` to the distinct accurate text `Click to review your history-access permission`; added `ComposerSettingsHubSystemTest` that checks no consent chip is named like Room settings, and verifies the genuine canonical Room sheet opens with an unsent human draft intact and zero messages sent. No access permission is granted from the chip, no previous test removed.

**All six exact-code-HEAD GitHub Actions SUCCESS on `edfd8685`:**
- Baseline Rails CI [44953386021](https://github.com/TheGor-365/turbo_chat/actions/runs/44953386021): **664 Rails runs / 10821 assertions / 0 failures / 0 errors / 3 inherited skips**; Redis distributed throttle 2/6 PASS; separate real Redis ActionCable 1/5 PASS; **full two-browser Chrome 177 runs / 2642 assertions / 0 failures / 0 errors / 0 skips**.
- Focused Chrome [44953386105](https://github.com/TheGor-365/turbo_chat/actions/runs/44953386105): **57 runs / 864 assertions / 0 failures / 0 errors / 0 skips**.
- Locale YAML integrity [44953386057](https://github.com/TheGor-365/turbo_chat/actions/runs/44953386057) SUCCESS.
- Security audit [44953386005](https://github.com/TheGor-365/turbo_chat/actions/runs/44953386005) SUCCESS.
- Docker smoke [44953386301](https://github.com/TheGor-365/turbo_chat/actions/runs/44953386301) SUCCESS.
- Production image build without deployment [44953386038](https://github.com/TheGor-365/turbo_chat/actions/runs/44953386038) SUCCESS.

**Classification:** D3.1a `CODE_CI_GREEN / OWNER_QA_PENDING` (not accepted; latest user local branch still known to be `3c7e784` with ` M db/schema.rb`). This status-only commit changes HEAD after the verified code SHA: inspect exact HEAD checks separately; don't mislabel it as identical code SHA. PR #8 stays DRAFT, no merge/Railway/paid AI/automatic Send/migrations.

**Owner next 1–3 actions:** safely `git status --short`, `git pull --ff-only origin feat/ai-answer-readiness-master-2026-11-20` preserving local `db/schema.rb`; run `docker compose exec -T web yarn build && docker compose exec -T web yarn build:css && docker compose restart web`; inspect `/rooms/3` six status badges, toggle Spelling (green→red→green), open **Instructions** as separate Plan-shaped sheet, and prove draft kept unsent. Then dark/light + mobile 390px and Plan→Message/Room. Owner screenshots needed for acceptance, D3.2 not started. QA guide: `docs/QA_D3_1A_STATUS_AND_INSTRUCTIONS_2026-11-22.md`; synthetic no-paid narrative: `docs/QA_SEMANTIC_DIALOGUE_AI_PIPELINE_2026-11-22.md`.


## Y. 2026-11-22 — owner B1 screenshots accepted partially; D3.1b localizable collapsible controls on draft PR #8

**Actual owner-local evidence:** `git pull --ff-only` fast-forward `3c7e784 → f8c8cf4` on `feat/ai-answer-readiness-master-2026-11-20`; `yarn build` and `yarn build:css` succeeded in Docker and web restart command completed. Only ` M db/schema.rb` appeared before pull and was preserved. Three owner screenshots of `/rooms/3` in Eric's private/incognito Chrome show all six status chips; Spelling toggled from green/On to red/Off, other real states reflected consent and available history, Auto Reply explicitly unavailable; Plan AI opens as a read-only bottom sheet. There was **no** test of standalone Instructions, draft sentinel preservation or mobile/light in those screenshots. No provider call or Send was intentionally tested.

**Owner request following screenshots:** (a) AI Plan `Effective preferences` displayed raw internal identifiers `friendly`, `ru`, `professional`, `room` despite RU interface. All displayed known enums must use current locale labels while server storage stays canonical. (b) Two composer rows must start at the same left edge: summary label/icon `Состояние`, below it `Настройки AI`; each independently collapses/expands with visible summary and smooth/reduced-motion compatible native accordion, no duplicated state setter. (c) Direct instruction entry should explicitly be named `Инструкции AI`.

**Feature-only code `d7990222056235c20f28015156693740fc093d11`:** original six chips and five task entrypoints are inside two initially expanded independent native `details` containers; summary stays visible when closed; accordion transition uses `::details-content`/native keyboard, Signal Deck colors, reduced-motion and 680px scroll/wrap rules. Existing controllers retain canonical owners; no separate preference persistence or permission toggle. The AI Plan uses `data-ai-answer-entry-preference-options-value` locale-specific option labels for existing enum values (profile/style/language/tone and Beautify one-shot), plus explicit locale keys for `room/account/system` source. Unknown user-authored custom text remains unchanged, not guessed. RU/EN/ES/HY added `aiSettings`, localized `AI instructions`, and origins. New browser test checks independent collapse, aligned summaries, retained unsent human draft and no Send.

**Additional test in this checkpoint:** an actual RU plan with inherited business account defaults asserts displayed `Аккаунт / Бизнес / Ответ клиенту / Русский / Деловой` and unchanged no-spend/no-Send state. These updates are not accepted until exact-newest-head six checks and owner screenshot. Do not claim every legacy/non-AI setting throughout the entire app was audited: scope is the visible composer and AI Plan values.

**Gate:** D3.1a `OWNER_B1_PARTIAL`; D3.1b `CODE_COMMITTED / CI_PENDING / OWNER_QA_PENDING`. D3.2/D3.3 remain NOT_STARTED. No DB migrations, no schema reset, no merge, no Railway, no paid provider. Next (1) check six workflow results on exact HEAD, patch reproducible Chrome issues without hiding tests, (2) owner safe ff-only pull/build/restart preserving local dirty schema, screenshot both rows expanded/collapsed and RU plan after reload, (3) owner Instructions, 390px/light and no-send acceptance before D3.2.


## Z. 2026-11-22 — owner D3.1b desktop screenshots; full execution plan re-baselined to R1

- **Owner local checkout:** `git status --short` showed only ` M db/schema.rb`; `git pull --ff-only origin feat/ai-answer-readiness-master-2026-11-20` fast-forwarded `f8c8cf4 → b52e614`; `git rev-parse --short HEAD` returned `b52e614`. Docker `yarn build`, `yarn build:css` succeeded and `docker compose restart web` returned to shell; not evidence of a new deployed service/production image in use.
- **Four screenshot observations at `/rooms/3` dark desktop:** two left-aligned Status/AI Settings rows expanded with six status chips and five buttons; both collapsed still show their text/icon summary; Russian AI Plan values `Дружелюбно / Русский / Деловой / Комната` readable; `Инструкции AI` opens canonical room settings dialog with revision 3 and template/revision section. Screenshots do **not** establish actual animation time, light/mobile, keyboard focus/Escape, no Send, privacy request trace or preservation of a typed unsent draft after navigation. Do not claim those passed.
- **GitHub exact-code HEAD:** `b52e614ff0b1088bba1c6440415293172ce9b126` PR #8 Draft; [Baseline 44959604368](https://github.com/TheGor-365/turbo_chat/actions/runs/44959604368) Rails 664/10821 (0 failures/errors, 3 skips) + Chrome 179/2669 (0 failures/errors/skips); Focused Chrome 58/876; six workflows SUCCESS including Locale/Security/Docker/image-build without deploy. Future docs commit requires checking its own exact HEAD checks.
- **Status update:** D3.1b `CODE_CI_GREEN / OWNER_DESKTOP_VISUAL_PARTIAL / OWNER_QA_PENDING`; G0 not fully ACCEPTED. D3.2/D3.3 `NOT_STARTED`. S0.2 backup/restore + local schema diff still `BLOCKED`; D3.4 server adapter, T2 paid live Answer, real Finalizer and R0/R1 not done.
- **Executor roadmap:** Existing master [§13](./AI_MVP_IMPLEMENTATION_MASTER.md#13-2026-11-22--исполнительный-план-от-d31b-до-mvp-r1-актуализация-существующих-std-не-замена-контракта) establishes G0→G12 mapped to existing S/T/D IDs with binary gates, no second roadmap or parallel storage. Immediate next G0 390px/light/unsent draft screenshots; then G2 D3.2 slim Beautify; G1 PG/media backup required before DB migrations.


## AA. 2026-11-22 — G0 owner mobile P1, code repairs and unaccepted Plan UX

**Evidence from user's latest screenshots at local `b52e614`, 400×793 responsive Chrome and desktop:** 1) composer single flex row shrinks unsent input `Тестовый, не отправляемый текст` into a near-vertical text strip; 2) message/room triggers become illegible icon-only actions; 3) message bubbles feel oversized, CSS actually set 15px desktop / 16px mobile; 4) AI Plan displayed no edit link to one-shot message settings, no readable saved room instructions, unequal card widths, a redundant own-draft/peer note; 5) standalone Instructions reused a large older native room dialog, no reciprocal one-click Plan path; 6) dark/light/system theme control exists already, monitor icon represents `system` (not evidence that Light is missing). Existing Context Studio, navbar/drawer and desktop dark/light themes are visually functional but mobile task panels still require targeted owner QA. The user's screenshots show **no accidental message sent**, but do not prove actual network/no-paid actions.

**Scoped GitHub Draft PR #8 feature commits:**
- `58c2a0d254a65142d48fa566f38237a37c37aeda`: targeted CSS mobile composer two-row grid, full-width human input, labeled 2-column message/room tools, 14px message bubble both breakpoints, 16px mobile textarea (avoid iOS focus zoom); new 390px Selenium layout/no-Send test.
- `b8ce49062857d0c626cc671e9221b47122ff17e3`: AI Plan displays saved `RoomAiInstructionRevision` preview as read-only, labels Beautify as own-draft-only without claiming the instructions were sent, adds canonical Message settings link, restores canonical Instructions navigation; 2-column equal-size Plan card rules and compact native Instructions dialog geometry; RU/EN/ES/HY keys; tests updated to check real state.
- `b3fd43e26b1536a64778fb563221f7a2089dfa02`: explicit Room/Message/Instructions → AI Plan reverse link, native dialog handoff without `finishClose`, guard unsent draft and paid/Send state in system test. Old nested Room↔Message nav remains until D3.2/D3.3 — do not label it migrated.
- `e455809118c627c5a6aec3bf5fcb4bb1a9d94e50`: narrow viewport system test had invalid `settings.querySelector` where `settings` was a DOMRect; changed test to query actual DOM Element. Code CSS was not changed by this fix.
- `2c5bb275decd780216282599cfc825c04c64ade6`: replace stale assertion demanding *removed redundant own-draft caption* with assertion that Beautify room instructions are **not transmitted** in this mode; no security invariant suppressed. Older focused runs correctly fail on pre-fix test versions and do not mean newest SHA is green/failed.

**At entry:** G0 `P1_PATCHED_CODE / EXACT_HEAD_CI_PENDING / OWNER_QA_PENDING`. Last **owner-confirmed local** `b52e614` with ` M db/schema.rb` protected; no owner pull of new commits, no production verification. Latest code SHA `2c5bb275...`; new docs-only commit triggers fresh SHA with its own CI. S0.2 backup/restore still blocked. D3.2/D3.3 not started. No data migrations, hidden provider calls, automatic Send, merge to main or Railway.

**Next gates:** verify six CI workflows on exact latest SHA, repair any real Chrome issue without deleting safety assertions. Only when green: owner safe ff-only pull, Docker JS/CSS rebuild/restart keeping local schema untouched, B5–B7 screenshots of 390/400px input and actions dark/light, Plan saved instructions↔canonical editor, Message settings navigation, unsent draft preserved. Until then G0 not accepted. See QA file below.


## AB. 2026-11-22 — G1 messenger-first mobile redesign

**Owner evidence:** five additional screenshots: existing desktop Context Studio modal, 400×793 mobile composer with human input a narrow text strip, mobile signed-in Home and desktop Home with marketing/large hero, desktop Activity & history with oversized header. Explicit owner requirements: 1) one consistent Plan-sized switching surface for status / Plan / Context / Instructions / Message / Room; 2) three primary mobile composer slots, **AI icon | elastic human input | one manual Send**; 3) Status, AI, Attachments collapse into modal workspaces above composer; 4) profile/theme/locale/logout behind top-right avatar dropdown; 5) logged-in root is real conversations-first home (chat links and create) not a landing page; 6) events/history prioritizes notifications, memberships and search, compact heading; 7) consistent 4-tab mobile bottom navigation. Actual screenshots are of **old owner local build**, not this branch's G1 commits. User accepts no premature automatic Send, misleading paid AI or KYC risks.

**G1 scoped feature PR #8 implementation milestones:**
- `a532869`: introduced mobile-composer-hub, narrow-screen three-column composer, full textarea between AI and human Send, mobile attachment selector and status/AI dialogs; shared tab navigation delegates to **original** controllers and does not copy consent/AI selection/persistence data.
- `abc8a3b`: signed-in Home now labels actual accessible rooms (up to 30), genuine unread counters, compact public/private create forms that redirect immediately using already existing Room/PrivateGroupsController. Guest home remains unchanged; no message bodies or denied room metadata. Mobile bottom tabs and collapsible quick actions.
- `cf2fe99`: avatar dropdown; `2d39150`: tabs use link semantics so previously mounted native buttons have unique names; mobile layout checks bottom alignment and 16px editable text.
- `d74e269`: Notification/Activity-first compact screen with native search preserved, grouped history, mobile nav.
- `2b12db0`: fixed unsupported strict SVG icons causing 500; relocated **original** theme button to avatar on mobile (never duplicate theme storage), updated existing foundation contract.
- `070be43`: home controller/localized tests assert new messenger requirements, membership/security unchanged.
- `bf7c991`: Context Studio adapted to same **bottom sheet geometry** on desktop/mobile; common Plan/Context/Room/Message/Instructions tabs track active native surface and new 390px no-Send switch test.
- `c6a20b5`: production cookie-backed smoke gate still checks HTTP 200/authenticated-only controls, now asserts new messenger home instead of removed marketing headline.
- `a9d2fc6`: one shared partial `_mobile_bottom_nav` used in Home, Inbox and Activity; isolated single chat retains its own conversation header/drawer and no bottom tabs.

**Architecture truth:** navigation feels like one AI workspace, but it still switches between multiple original native dialog/panel DOM elements. This is **not yet a one-root unified dialog or a full UX acceptance**. Status and attachment windows are separate from AI inspector (as owner intended) and no model payments, auto Send, migrations, DB schema, production deploy or main merge were introduced. Actual context source-selection persistence and room instruction revisions still owned by prior canonical controllers. Mobile avatar menu only, desktop standard top nav preserved. The 4-tab bottom menu currently appears Home/Inbox/Activity; standalone profile route has its own account layout, which is still a separate future normalization.

**CI defects repaired while implementing G1:** new shared tab buttons duplicated canonical button labels in Chrome; converted to navigational links while retaining original buttons. Initial new Home threw HTTP 500 because `arrow-right`/`chevron-right` were not in `SignalDeckHelper::ICONS`; replaced with `arrow-up-right`. Theme was briefly duplicated; replaced with moving the one original theme controller target. Production smoke still matched deleted English headline, now checks membership-root signed-in messenger structure while preserving cookie check. Earlier failed intermediate commits are not the verdict on the newest SHA.

**Status at this write:** `G1 CODE_COMMITTED / LATEST_SHA_CI_PENDING / OWNER_BROWSER_QA_PENDING`. Source PR https://github.com/TheGor-365/turbo_chat/pull/8 . Latest code commit before this documentation `a9d2fc695457b7774031844eac3c1146e6a5b77b`; docs commit will produce a new exact HEAD and rerun CI. Last user-confirmed local `b52e614`, with ` M db/schema.rb` protected. Do **not** recommend user pull or accept G1 until exact HEAD 6/6 CI success. G0 and G1 cannot be accepted from server CI screenshots alone. D3.2/D3.3 full migration of all five canonical surfaces into one native dialog remains future, and P0/P1 mobile owner review can require more changes. No deleted repositories, assets, Rails data.

## AC. 2026-11-22 — G1 exact-HEAD baseline failures and scoped repair (unaccepted)

**Source:** PR #8 exact G1 HEAD `d62baafdf0ca2dfeacbcaeec961235888cfb5c98`, Baseline Rails CI [44967008591](https://github.com/TheGor-365/turbo_chat/actions/runs/44967008591). Security, Locale YAML, focused Chrome, Docker smoke, production-image build **SUCCESS**; Baseline Rails **FAILED**. Rails **664 runs/10826 assertions/0 failures or errors**, Redis throttle **2/6** PASS, standalone cross-process ActionCable **1/5** PASS. Full Chrome **184 runs / 2673 assertions / 3 failures / 5 errors**.

**Diagnosed:** legacy mobile system tests still required a permanently visible navbar Settings/theme toggle, even though G1 moves profile and the *one canonical theme button* behind avatar. Narrow-viewport AI editor/coverage tests sought a hidden desktop-only “Edit unsent message” button rather than the G1 mobile AI-workspace path. G1 Activity Back was 40px, below existing >=43.5px accessibility acceptance. Private presence final offline transition failed once after explicit unsubscribe: **UNRESOLVED_FLAKE_OR_REGRESSION**; no test suppression or premature fix claim.

**Scoped patch:** align affected Selenium steps with the real visible avatar/workspace navigation, keep assertions for actual editor/room sheet opening, unsent draft, permissions and responsive geometry. Raise Activity Back and quick navigation touch target to 44px. No tests removed. Require all six workflows on new exact HEAD; investigate presence separately if recurrence.

**Status:** `G1 PATCH_COMMITTED / EXACT_HEAD_CI_PENDING / OWNER_QA_PENDING`; D3.2 not started. No main merge, Railway deployment, DB migration, local schema reset, paid provider or auto-send. Preserve local ` M db/schema.rb`. Owner B8–B12 390–400px/light/dark acceptance remains outstanding.
