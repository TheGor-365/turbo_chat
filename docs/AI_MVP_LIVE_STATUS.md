# TURBO CHAT V2 — LIVE STATUS / ЕДИНАЯ ТОЧКА ПРОДОЛЖЕНИЯ
**Снимок проверки:** 2026-11-21. **Сначала перепроверь HEAD, PR #8, Actions и код!** Эта запись не автообновляется после чужих коммитов.
**Продуктовый master:** [AI_MVP_IMPLEMENTATION_MASTER.md](./AI_MVP_IMPLEMENTATION_MASTER.md).
**Текущая ветка:** `feat/ai-answer-readiness-master-2026-11-20`.
**PR #8:** https://github.com/TheGor-365/turbo_chat/pull/8 — draft, open, base `feat/s3-s6-ai-answer-gated-2026-11-20`, `main` не затронут.

## A. Последний реально наблюдавшийся owner state (не выдумывать новые факты)
- Owner terminal 21.11: локальный `git pull --ff-only` получил `a231da4`; `yarn build` и `yarn build:css` SUCCESS; `docker compose restart web` выполнен до завершения возврата shell. Не подтверждено, что web health и браузерная приёмка после restart успешны.
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
| S8.1 | PARTIAL | SourceSelection/Coverage/Evidence/H4/H5 есть; единая named dynamic modal/сохранённые наборы не реализованы |
| S8.2–S8.4 | SPEC | **AI Finalizer с Summary по умолчанию НЕ реализован**; старая H4/H5 проверка/экспорт != real AI summary |
| S8.5 | PARTIAL | исторические source checks есть, полная инвалидация сохранённых наборов ещё не существует |
| S9.1–S9.4 | BLOCKED | Турбо Чат не подтверждён в отдельном Railway R0/R1 |
| S10.1–S10.4 | SPEC | tenant API/widget/commercial pilot не завершён |
| D0–D2 | PARTIAL | старые Signal Deck UI, theme, native-backed select есть; полный аудит/консолидация token не подтверждены |
| D3 | PARTIAL | AI Plan в композере; еще нет одной полной конфигурации четырёх режимов |
| D4 | PARTIAL | RU/EN/ES/HY отдельные slices есть; весь Workspace и Review не принят |
| D5 | SPEC/PARTIAL | созданный source editor != новый modal с virtual chat + toggles + сохранёнными наборами |
| D6–D7 | SPEC/PARTIAL | отдельные responsive/keyboard тесты есть, полный visual/a11y gate не пройден |

## E. Непосредственно следующий прогон (не возвращаться к ранее закрытым этапам)
**E1 — GitHub CI, только последний HEAD**:
- после коммитов этого статуса проверить PR #8 Actions. Если тесты красные, считать T1.3 не закрытым; для каждого сценария выписать точный assertion/HTML state и внести минимальное исправление без подмены поведения. Полный Rails CI, focused Chrome, Docker, security и image build — на SAME head. Не переносить успех `a231da4` на новый HEAD.
- Никаких новых миграций/деплоя/платного AI.
**E2 — owner локально после успешного pull (сохранить `db/schema.rb`)**:
1. `git status --short && git pull --ff-only origin feat/ai-answer-readiness-master-2026-11-20`; если FF отказ, остановиться и изучить `git status -sb` без `reset --hard`.
2. `docker compose exec -T web yarn build && docker compose exec -T web yarn build:css && docker compose restart web` и дождаться завершения, проверить `docker compose ps`.
3. Browser: Project Circle → «AI plan» → снять M35 при оставшемся M33; expected target M33; «Применить к AI Answer» → visible saved confirmation, контекст обновился, карточки не мерцают. Сменить профиль/язык, сохранить; редактировать инструкцию, сохранить; visible green confirmation вне closed details; проверить после reload и Room settings. **Не нажимать платный Answer**. Пришли screenshot или точную ошибку.
**E3 — после E1+E2:** T1.3 `ACCEPTED` → T1 compact settings de-duplication → T2 one controlled real AI Answer call *только с отдельным согласованием разрешений и бюджета*, synthetic room and PG ledger inspection. Параллельно backup/evidence QA для S0.

## F. Обновление этого документа
Каждая следующая сессия обязана:
1. Прочитать current PR/HEAD/CI, сравнить с этим snapshot.
2. Обновить изменённые строки ID только доказательствами: `timestamp | ID | status | SHA | exact test runs | user QA | linked issue/PR | next gate`.
3. Делать **новый** commit `docs(status): checkpoint <ID> <result>` после кодовых изменений и проверять CI на новом HEAD. Если status stale — не считать старую отметку green.
4. Не менять прошлые `ACCEPTED` в `SPEC` без конкретной регрессии. Не переписывать master, если меняется только статус.
