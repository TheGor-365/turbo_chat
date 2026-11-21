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
| S8.1 | IN_PROGRESS / OWNER_QA_PENDING | D5.1: consent-scoped paginated full-history Context Studio в PR #8; четыре базовых пресета, динамические switches, локальные sets, bounded Answer only; server sets/full-retrieval не готовы |
| S8.2–S8.4 | SPEC | **AI Finalizer с Summary по умолчанию НЕ реализован**; старая H4/H5 проверка/экспорт != real AI summary |
| S8.5 | PARTIAL | исторические source checks есть, полная инвалидация сохранённых наборов ещё не существует |
| S9.1–S9.4 | BLOCKED | Турбо Чат не подтверждён в отдельном Railway R0/R1 |
| S10.1–S10.4 | SPEC | tenant API/widget/commercial pilot не завершён |
| D0–D2 | PARTIAL | старые Signal Deck UI, theme, native-backed select есть; полный аудит/консолидация token не подтверждены |
| D3 | PARTIAL | AI Plan в композере; еще нет одной полной конфигурации четырёх режимов |
| D4 | PARTIAL | RU/EN/ES/HY отдельные slices есть; весь Workspace и Review не принят |
| D5 | IN_PROGRESS / OWNER_QA_PENDING | Single Context Studio modal added; old AI Plan source editor removed. Full room UI inventory до 10k; server-persisted sets, full retrieval, AI filter, full cross-mode integration ещё SPEC |
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
