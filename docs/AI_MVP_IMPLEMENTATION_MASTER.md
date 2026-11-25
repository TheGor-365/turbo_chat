# TURBO CHAT V2 — AI MVP MASTER / ПОШАГОВЫЙ ПЛАН ДО ПРОДАКШЕНА
Версия 2026-11-21. **Нормативный продуктовый контракт и backlog; НЕ отчёт о выполнении.**
Репозиторий: https://github.com/TheGor-365/turbo_chat
Активная интеграционная ветка на дату составления: `feat/ai-answer-readiness-master-2026-11-20`, draft PR https://github.com/TheGor-365/turbo_chat/pull/8.
**Операционная точка входа и текущие доказательства:** [AI_MVP_LIVE_STATUS.md](./AI_MVP_LIVE_STATUS.md). Её обязательно читать после получения текущего GitHub HEAD/CI. Этот master фиксирует *что нужно*, но никогда не подменяет проверку *что сделано*.

## 0. Правило приоритета источников и работы новых чатов
1. Сначала GitHub: `get_repo`, head текущей рабочей ветки/PR, последние commits, `git diff`, изменённые files и Actions на **точном SHA**; затем существующий код, тесты, Rails routes и миграции. Проверить, не ушёл ли PR вперёд и нет ли другого активного потока разработки.
2. Затем `docs/AI_MVP_LIVE_STATUS.md` и этот master; затем [existing ADR 2026-11-20](./ADR/2026-11-20_SHARED_AI_ENGINE_MASTER_V1.md), ранее принятые ADR и дизайн Signal Deck 2 / Quiet Depth (спецификация пользователя от 17.11, не считать автоматически загруженной в GitHub).
3. При конфликте: **актуальный код + точный SHA + CI + ручная проверка + серверное состояние** важнее обновляемого live status; live status важнее этого master; master важнее старых roadmap. Устаревший пункт помечать `REPLACED_BY` со ссылкой, не переделывать.
4. Статус каждого ID: `SPEC` (требование), `EXISTS_CODE` (обнаружен код), `PARTIAL`, `IN_PROGRESS`, `BLOCKED`, `CI_FAILED`, `CI_GREEN`, `OWNER_QA_PENDING`, `ACCEPTED`, `DEPLOYED`, `DEFERRED`, `REPLACED_BY`. Нельзя писать `DONE` только по коммиту или успешной сборке.
5. На каждый законченный срез: проверить уже реализованное; внести минимальное исправление в существующие компоненты (не вторую БД/контроллер/дублирующую панель); написать тесты; получить SHA; проверить Rails/Chrome/security/production image; определить Owner QA; обновить live status **отдельным коммитом**; показать 1–3 действия владельцу. При новом изменении status-commits запускается CI заново: не переносить успех прошлого SHA на новый.
6. Не делать merge в `main`, production deploy, платные AI-запросы, реальные сообщения от имени пользователя, разрушительные изменения БД или удаление volume без явно согласованного релизного шага. Не запрашивать и не печатать ключи/PII/коммерческие переписки.

## 1. Продуктовый контракт: ровно четыре AI-возможности на одном ядре
| Mode | Название в UI | Правило ввода | Результат | Автоматизация |
|---|---|---|---|---|
| `beautify` | AI Beautify / Улучшить | Исходный человеческий черновик **не пуст** | Отдельный редактируемый вариант, сохраняющий факты | По умолчанию только явное нажатие |
| `answer` | AI Answer / Предложить ответ | Композер человека **пуст**; есть разрешённая цель/контекст | Новый редактируемый ответ на входящее | Только явный запрос, отдельная отправка |
| `auto_reply` | AI Dialogue / Автоответ | Событие/триггер с опубликованной политикой | Сначала dry-run, позже условный автопост | Выключено по умолчанию; собственный выпускной gate |
| `finalize` | **AI Finalizer / Итоги диалога** | Явно выбранная разрешённая история, не зависит от draft | Именованный редактируемый результат; **пресет по умолчанию «Резюме беседы»** | Выключено по умолчанию; отдельное opt-in расписание |

**Почему Finalizer:** `Resume` неоднозначно (CV/резюме); `Finalizer` — название категории, `Summary`/«Резюме беседы» — одна из задач. Внутренний старый `AiDeliverable`/H4/H5 повторно использовать, не дублировать документы только ради нового имени.

Общие непреложные правила: человеческий и AI варианты раздельны, оба редактируемы, отдельные Send. Никакой генерации при наборе текста, переключении вкладок, смене настроек или открытии панели. Нет принудительной отправки вложений из другого поля. Нет изобретённых цен, сроков, подтверждённых договорённостей и фактов. Provenance, consent, расходы и ревизии проверяются сервером после ответа провайдера и непосредственно перед Send.

## 2. Один центр настроек: общие defaults + различия режимов
**Цель UX:** пользователь настраивает один раз весь AI, затем при необходимости точечно переопределяет функцию. Никаких четырёх независимых копий тон/язык/профиль/цель. Разные экраны могут ссылаться на **одну** серверную модель/резолвер.

2.1. **Уровни хранения и precedence:**
- Immutable server policy: ACL, tenant isolation, consent, allowed sources, protected system prompt, лимиты — UI не может переопределить.
- Account defaults → личная настройка в комнате → общий **режимный override** (`beautify/answer/auto_reply/finalize`, только при явном «Настроить отдельно») → одноразовые настройки текущего действия.
- Общая room instruction/goal revision подключается отдельно; цель комнаты не равна личной стилистике. Персональная цель и общий purpose могут существовать параллельно, но их конфликт должен быть виден.
- У каждой настройки показывать происхождение: «аккаунт», «комната», «отдельно для функции», «только этот запрос». Кнопка «Вернуть общие» удаляет только override, **не** стирает master-настройки.

2.2. **Один Settings/Generation Inspector** в task sheet около композера (не четыре страницы): верхняя сводка «Что сделает AI»; компактные пресеты «Обычный», «Деловой», «Дружеский», «Обучение», «Знакомства» (проверить фактический существующий каталог); стиль, тон, длина, язык ответа, emoji, формат, инструкции; «Источник контекста»; «Сценарий AI»; «Приватность и цена». Настройки комнаты, аккаунта, одноразовые и сценарии визуально различаются, но направляются к существующим endpoints. Кастомные инструкции не обладают системными правами.

2.3. **Preset/playbook:** один клик применяет осмысленный непротиворечивый набор видимых модификаторов; можно вручную выключить/включить, сохранить под именем, дублировать, сделать версию, сравнить effective diff. AI-редактирование сценария — **отдельно подтверждённая платная операция**, результат как предложение, вручную Apply/Undo. Существующие RoomAiInstructionRevision и local/saved templates изучить до решения о миграциях.

2.4. **UI:** фирменные переключатели `role=switch` с aria, а не визуальные HTML checkbox; существующий `ui_select_controller` (native-backed semantic fallback), не браузерный popup и не новый конкурирующий select. Анимация 120–300ms с reduced-motion; не терять input/scroll/attachment; все UI-строки RU/EN/HY/ES.

## 3. Контекст: общий и режимный, полный доступ ≠ слепая пересылка
3.1. Для каждого разрешённого участника по умолчанию **вся eligible история комнаты** является *кандидатами* для ответа **после consent**. Нельзя утверждать, что текущие 240 candidate / 9 excerpts / 2400 chars означают «вся история». Для большой истории: paginated full inventory → точные фильтры/индекс → retrieval/summaries → source-backed selected excerpts. Показывать `total/scanned/eligible/selected/used/truncated/denied` честно.
3.2. **Конфигурация источников**: общий room default, optional per-mode override, optional one-shot override. «Сбросить к общему» восстанавливает наследование без потери сохранённых пресетов. Файлы — отдельный grant и не включаются автоматически.
3.3. **Модальное окно «Выбор контекста»** (новая оболочка поверх существующих SourceSelection/Coverage):
   - список/виртуализированный чат с аватарами, датой, человеком, текстом, вложением-метаданными, ID; фильтры search/date/participant/topic/type; multiroom не включать без нового ACL и отдельной спецификации;
   - переключатель для каждого сообщения включён по умолчанию *в рамках eligible subset*; при OFF bubble приглушается, остаётся видимой, count и показатели каждого автора обновляются без reload; «выключить участника» немедленно исключает его сообщения из видимого выбранного набора (с восстановлением);
   - сводка eligible/selected/excluded и per-user, прогресс, пустые и restricted states, возможность отката/сброса/preview; плавные transition, reduced-motion, 320/360/390 mobile, клавиатура;
   - текст «Оставь сообщения о проекте X» = **AI-фильтр-предложение**, не мгновенный скрытый write, не запуск без consent/бюджета. Сначала показать `before → after`, uncertain matches, Approve/Undo, модель/стоимость;
   - если выбранная цель ответа исключена, автоматически выбрать **последнее оставшееся разрешённое входящее**; свои сообщения можно оставить как контекст, но не как incoming reply target; если нет входящих — блокировать Apply с объяснением;
   - предварительное состояние UI сохранять от случайного закрытия, но **серверный reusable snapshot** создавать только после «Создать набор» → обязательное имя (предложение `<room> · <locale datetime>` с timezone пользователя) → подтверждение. Имя можно редактировать; для выбранного набора хранить фильтры и ID/версии/ACL fingerprint, не только красивое название;
   - при изменении message/ACL/consent/goal revalidate и stale badge; выбор не может расширять серверное разрешение. В shared room нельзя предполагать согласие второго участника.

3.4. **Для Finalizer:** один активный набор контекста, список ранее сохранённых наборов с кнопкой «Использовать», «Изменить копию», «Удалить». Экспорт/документ имеют ссылку на версии источников, дату/пользователя, входные параметры, модель, prompt revision.

## 4. Архитектура без параллельных реализаций
4.1. **Сначала аудит существующих объектов:** `AiWorkspace::GenerationOrchestrator`, `GenerationInputContract`, `WritingPreferenceResolver`, `AiRoomWritingPreference`, `AiAccountWritingPreference`, `RoomAiInstructionRevision`, `RoomInstructionGoal`, `RoomContextAccess`, `AiRoomContextConsent`, `ReplyContextBuilder`, `SourceSelection`, `DraftProvenance`, `AiDeliverable`, H4/H5 review/export и экспериментальный S7 на другой ветке.
4.2. **Целевой интерфейс:** один `EffectiveGenerationPlan` (концептуальное имя, **не** свидетельство существующего класса): mode, goal and revision, effective preferences + inheritance, modifiers/script revision, server-approved snapshot fingerprint + source IDs, permission fingerprint, tool and media capability, actual model, quotas/cost ceiling, warnings. Детерминированный compile; модели получают untrusted snippets/data, не полномочия.
4.3. Подключить 4 режима к одному интерфейсу по вертикальным срезам, не переписывать уже работающий Answer ради архитектуры. Beautify own-draft-only доступен без истории и обязан работать даже при запрете контекста. Связанный контекст Beautify — **отдельный opt-in**, shared consent. Auto Reply оборачивает тот же plan policy worker'ом; Finalizer использует те же snapshot/ledger/provenance, но иной result type, не отправляет message без явного действия.
4.4. Контракт результата: content, structured citations, used source ID+version, effective mode/preset, language, unit cost/settled ledger, provenance fingerprint, stale flag, warning/review state. Проверить перед публикацией. Парсинг/ошибка провайдера не отправляют «готово», максимум safe failure.
4.5. Производительность: индексированная выборка, pagination, size limits, доступность больших комнат, backpressure. Нельзя копировать тысячи private сообщений в browser state или prompt при каждом открытии.

## 5. S0–S10: точные шаги и Definition of Done
**Это полная структура целевой программы. Статусы сверять только с LIVE_STATUS; описанные здесь операции не означают реализацию.**

### S0 — целостность и инвентаризация [RELEASE FOUNDATION]
- S0.1 Повторить M33/M34: evidence confirm → re-search → persisted → revoke → re-search, owner screenshot + backend test.
- S0.2 Проверить локальный PG/media backup, isolated restore, отличие `M db/schema.rb`, не сбрасывать; перед каждой новой миграцией свежий backup.
- S0.3 Проверить AI-panel в реальном браузере; фиксить лишь подтверждённые дефекты.
- S0.4 Зафиксировать V2 contract/docs, ветку, CI, данные, текущие blockers.
- **DoD:** данные сохранены; restore показан; действия M33/M34 переживают reload.

### S1 — composer / AI action [UI FOUNDATION]
- S1.1 Пусто → Answer; не пусто → Beautify. Нет скрытой генерации при вводе.
- S1.2 Inline readiness: цель/consent/provider/budget; кнопка явного исправления каждого blocker, без сюрпризного перехода.
- S1.3 Два редактора, отдельные explicit Send, отсутствие переноса вложений, keyboard + mobile + resize + reduced-motion.
- S1.4 One-shot настройки и regenerate с отдельным экономическим подтверждением; stale candidate не публикуется.
- **DoD:** все smoke/Chrome tests и owner QA; ни одна смена UI не расходует токены.

### S2 — цели и единые настройки [FOUNDATION]
- S2.1 Account/room goal, permissions/ACL, revision + multi-tab conflict; verify persistence.
- S2.2 WritingPreferences account/room + one-shot precedence, 1 место для UI редактирования, реальные источники значений.
- S2.3 One shared default, optional per-function override, easy return to defaults; no duplicate storage.
- S2.4 Компактные пресеты, modifiers, custom instruction, locale/output tone/length/emoji; i18n.
- S2.5 Effective plan preview (no AI spend); apply/confirm status remains visible after UI refresh.
- **DoD:** settings saved/reloaded in two browsers; version conflicts safe; effective settings same across modes unless explicitly overridden.

### S3 — единый engine [FUNCTIONAL PRIORITY]
- S3.1 Audit existing Orchestrator/InputContract/legacy generation; reuse, don't replace.
- S3.2 Deterministic compiled contract for Beautify, Answer, Auto Dialogue (gated), Finalizer.
- S3.3 Goal + preferences + full eligible coverage contract + selected sources + immutable ACL/consent.
- S3.4 Source versioning, post-provider reauth, stale invalidation (editing/deleting/member change).
- S3.5 Source-backed output, warning, provenance/cost/provider metadata, quality/unchanged state.
- **DoD:** one flow for manual answer and contextual beautify, no unsafe send or second billing path.

### S6 — production AI / accounting [RELEASE BLOCKER; раньше S4/S5]
- S6.1 Verify provider model, live API eligibility, actual prices/retention by current official docs, fallback.
- S6.2 PG atomic reservations/settlements/reconciliations for all modes; idempotency/unknown cost states.
- S6.3 User/room/request/day/month limits, rate limits, per-tenant policy, kill switch.
- S6.4 One explicit request; no infinite retry, crash-safe reconciliation, provider timeout handling.
- S6.5 Secrets only deployment environment, redacted logs and privacy, operator dashboard.
- **DoD:** 100% provider paths require consent (where context) and budget; concurrency and failure tests prove bounded spend.

### S4 — i18n messaging [FUNCTION]
- S4.1 UI locale, reading translation language, outgoing answer language separately per member.
- S4.2 Browser on-device translation if supported and truthful original/fallback behavior.
- S4.3 External fallback only after per-user consent and budget check.
- S4.4 RU↔EN, KO→EN, HY→EN, IS→EN plus mixed-locale group regression.
- **DoD:** unsupported pairs do not pretend successful translation; source untouched.

### S5 — knowledge assets [FUNCTION]
- S5.1 `AiKnowledgeAsset` **candidate model only after storage audit**; separate from chat attachments.
- S5.2 TXT/MD/CSV/PDF imports with MIME validation, malware/size, version/ACL/TTL, signed access.
- S5.3 Retrieval/chunks/source citations for document evidence; no prompt instructions as authority.
- S5.4 Invalidation on edit/delete/revoke, no cross-room/tenant access.
- **DoD:** grounded answer with source reference; absent stock/price/date not hallucinated.

### S7 — AI Dialogue [AUTOMATION; GATED]
- S7.1 Readiness 0–100% means **configuration completeness** only, never answer accuracy.
- S7.2 Explicit policy `off/suggest/auto_limited`, allowed topics, working hours, delay/jitter, cooldown/limit.
- S7.3 Durable queue and run journal; idempotency, no AI-to-AI ping-pong; ownership/consent.
- S7.4 Dry-run only first; review suggestions + costs before enabling; auto-send requires separate opt-in gate.
- S7.5 Kill switch: human takeover, revocation, changed goal, unknown claim, limits/budget exhausted.
- **DoD:** one valid response max per source event, no hidden tokens, automatic sending separately approved and tested.

### S8 — AI Finalizer / работа с диалогами [FOURTH CORE CAPABILITY]
- S8.1 One modal selection tool with participants/date/search/message toggles, live counts/disabled look, saved named configuration. Reuse H4/H5/Coverage/Evidence/SourceSelection.
- S8.2 MVP presets: **Summary/Резюме беседы (default)**, decisions, tasks+owners, open questions, risks, brief, timeline, document draft/export; source backed, mark uncertain.
- S8.3 Result editor: human edit, AI-assisted revision only explicit paid click, compare/undo, versioned named save, export MD/TXT/PDF if supported; never fabricate unsupported formats.
- S8.4 Optional `every N messages` (e.g. 10) summary: opt-in, count eligible events reliably, dedupe, budget, notification and no auto-send; never enabled by default.
- S8.5 New message/delete/revocation invalidates selected snapshots and stale result; strict room ACL.
- **DoD:** 2+ participant room has meaningful human-readable summary with citations and edit/export; no ungrounded decision/commitment; default Summary ready only after actual implementation.

### S9 — Railway, R0 / R1 [RELEASE]
- S9.1 R0 isolated Railway project, synthetic identities, Postgres+Redis+durable attachment storage, HTTPS/WSS; budget and backup approval.
- S9.2 Security/observability, storage/PG restore, privacy controls, CSP, rollback, two-browser flow.
- S9.3 R1 production AI for approved modes, quotas, settings, language/knowledge, Finalizer; AI Dialogue auto remains off until specific gate.
- S9.4 Explicit failure matrix: consent revoke, stale goal, provider outage, retry/concurrency, broken translation, file restore, kill switch.
- **DoD:** deployed exact SHA, CI+two-browser/smoke+restore green, spend controlled, user signs off; R0 is NOT R1.

### S10 — integrations and commercial pilot [AFTER R1]
- S10.1 Scoped tenant-auth API, key revoke, audit and quotas.
- S10.2 One embedded iframe/widget in test site, origin isolation, CSP and no secret/client data leakage.
- S10.3 Trial accounts separated; pricing/COGS/tenant spend monitored; explicit invoice/payment route compliant with local IP.
- S10.4 First real transaction and usable funds documented; real feedback/retention.
- **DoD:** genuine paid and usable revenue + stable widget + no cross-tenant data leakage.

## 6. D0–D7: дизайн-программа параллельно, без переписывания backend
- D0 Inventory exact screens, CSS/Stimulus and browser before screenshots (both themes).
- D1 Single semantic Signal Deck tokens dark/light/system, field contrast, scrollbars, typography.
- D2 Reuse SD icon/avatar/card/switch/ui-select; no browser popups or visible checkboxes in enhanced experience; accessible fallback.
- D3 One settings task sheet for all 4 AI functions; source/goal/preset/script UX, no competing Workspace, no state loss.
- D4 Complete RU/EN/HY/ES for Workspace, document review, system errors, source stats.
- D5 Target-context room-chat modal + filters + live counts + named saved selections + Finalizer navigation.
- D6 Chat/profile/notifications polish, stable scroll+draft, keyboard and screen-reader state.
- D7 320/360/390/430/600/768/1024/1440/1920, 200% zoom, light/dark/system, reduced-motion, a11y; end-to-end under real browser. **Design accepted only after accessibility + CI + owner QA.**

## 7. Execution slices T0–T8 (crosswalk, not parallel replacement of S stages)
- **T0:** Answer readiness inline blocker = S1.2, S2 prerequisite.
- **T1:** compact shared plan/settings/source UX and persistence = S2.2/S2.5 + D3.
- **T1.3:** dropdown/target feedback/browser acceptance and CI repair; next unresolved local owner QA (see live status).
- **T2:** one explicit *real* dev Answer call with synthetic chat, all consent, no send, actual PG cost = S3/S6 proof. Only after T1 tests/QA and user cost consent.
- **T3:** contextual Beautify using shared plan, own-draft-only option, PG ledger = S3.
- **T4:** modifiers + saved script revision + one center with per-function override = S2/S3/D3.
- **T5:** truthful full eligible-history + optimized source selection/reusable named snapshot with dynamic modal = S3/S8/D5.
- **T6:** knowledge + multilingual + full Finalizer MVP (do not conflate with legacy mock document export) = S4/S5/S8.
- **T7:** AI Dialogue guarded dry-run + safe policies/worker = S7.
- **T8:** Railway R0→R1 acceptance + API/widget/pilot = S9/S10.
**Ordering:** unblock current T1.3 before T2; smaller D changes parallel. If actual code already covers a later slice, mark `EXISTS_CODE`, verify its tests, and advance; NEVER reimplement from description.

## 8. Tests / quality matrix required before marking ACCEPTED
- Account/room member ACL, foreign/removed member, public-vs-private, sharing and revocation.
- M33/M34 evidence confirm/persist/revoke; M35 exclusion when target, auto replacement by latest eligible incoming; no incoming blocks Apply; own messages never reply target.
- Native-backed SDSelect keyboard/popover fallback; `visible: :all` for native select in Capybara; **visible feedback** after saving (must NOT be trapped in collapsed <details>).
- Composer empty/nonempty transition without paid API; independent Send/attach/draft, click-only generation and explicit budget.
- Multi-tab settings revision conflict; Account→Room→Mode→One-shot precedence and "restore shared".
- Whole-history coverage truthful; content filters, named saved selection, ACL fingerprint, stale revocation; avoid cross-tenant leak.
- Beautify protects negation/technical strings and reports unchanged_compliant honestly.
- Summary includes decisions/tasks/open questions only if present, citations/source versions, proper human/AI edit, export.
- Auto dry-run/worker exactly-once, cooldown, kill switch, no message loop.
- CI Rails, focused/whole Chrome, Security audit, Docker smoke, production image **all at same HEAD**, owner browser on dark/light/mobile. A successful build or tests on a prior SHA are not final acceptance.

## 9. Fixed operational rules
- Changed `db/schema.rb` in owner local working tree: do NOT reset, stash, overwrite, delete, migrate over or commit blindly. Owner first examines safe diff, DB backup/restore and intended migrations. No `db:drop`, `db:reset`, volume pruning, `git reset --hard`.
- Branch PR #8 is draft, base `feat/s3-s6-ai-answer-gated-2026-11-20`, NOT `main`. PR #2/old S7 branch is not a source of working auto send.
- Production xAI is not proven. Current Answer path is development-gated and SourceSelection is bounded; never call it without private test accounts + all grants + user approval of maximum cost.
- Secrets in gitignored local environment only; diagnostics print gate booleans, never token values or private transcript.
- New status record format: `YYYY-MM-DD | ID | previous → current status | exact SHA/path/CI run | tests | owner QA | blocker | next ID`. Keep original ID stable, record `REPLACED_BY` if scope changed.

## 10. Boot prompt for every new development chat
> Ты инженер-исполнитель Turbo Chat V2. Не начинай с проектирования заново. Открой GitHub `TheGor-365/turbo_chat`, прочитай draft PR #8, сравни актуальный HEAD и CI, прочитай `docs/AI_MVP_LIVE_STATUS.md`, затем `docs/AI_MVP_IMPLEMENTATION_MASTER.md`, актуальные ADR и существующий код. Старый master — контракт, не свидетельство реализации. Если ID уже реализован, не дублируй: проверь доказательства и сдвинь статус. Если есть CI failure — сначала чини минимально на текущей ветке, не обходя тесты. Приоритет сейчас T1.3 owner QA/CI → T2 real Answer only after explicit cost+consent → T3 contextual Beautify → T4 settings/script → T5 contextual picker → T6 Finalizer. Не создавай новые хранители тех же prefs/goals/templates. Держи 4 mode в одном серверном контракте; default всей authorized истории означает eligible candidate pool, а не гарантированную пересылку текста. Не запускай API/деплой, не меняй main, не трогай локальный `db/schema.rb`. В конце каждого шага сохрани GitHub commit с ID (например `fix(T1.3/S2.5)`), проверь exact-SHA Actions и обнови LIVE_STATUS. Дай владельцу только 1–3 шага с ожидаемым состоянием, собери скриншот, отметь `ACCEPTED` лишь после подтверждения.


## 11. D3.1–D3.7 — консолидация UX настроек/действий (решение владельца 21.11.2026)

**Источник решения:** screenshots owner at 20:54–21:20 on /rooms/3; separate Context Studio now works and has two different effective selections, but legacy draft/room task sheets remain crowded and source review duplicates source selection. No proposed new backend store without audit.

### One-source-of-truth UI and scope
- **Exactly four primary composer entrypoints for now**: `Контекст AI`, `План AI` (read-only effective status), `Сообщение` (Beautify/draft; edits one unsent message), `Комната` (room policy, writing, instructions, consent, display). Icon, dimensions, stroke and hover/focus all Signal Deck. No second menu popover around these entrypoints; click outside a modal or Escape closes it without mutating draft/ACL.
- **Context Studio exclusively owns source selection**. No duplicate source list/selection, participant/date/keyword controls in draft editor, room settings, Plan, document editor or consent drawer. Legacy H3 source-review/coverage/evidence backend is NOT deleted until actual provider input of all modes compiles via the same validated selection contract. If old source UI is retired, its known integration tests are migrated or an explicit legacy-debug-only fallback is gated. No silent removal of developer evidence/fact-check tools.
- **Beautify = message editor**, not a separate fifth AI settings page. One working text, three fast style presets + compact expandable full preset list, inline status & one Apply-to-message action; no second configuration for context. Preview/Undo/unsent draft/attachment retention unchanged. A user is never asked to edit the same property twice in two panels. AI Answer remains explicit before real model billing.
- **Room**: canonical `AiRoomWritingPreference` (profile, style, language, tone; account fallback) + append-only `RoomAiInstructionRevision` and existing consent. Show current effective values only once. Compact icon profile presets, custom style picker and consent toggles with scope in UI, device/account/room basis, no ambiguous «saved» label. Named room-instruction templates remain browser-local until planned server sync; name editable *inline* from original current title and revision; rename does not create a message or another instruction revision.
- **Message**: compact quick presets in single selector (clarity, client reply, friendly, etc), optional custom text instruction bound to this draft only; no conflict with room policy or source context. Changes remain explicit: preview, apply, undo; never send on Apply.
- **Document/Finalizer**: compact category presets such as conversation summary (default), decisions, tasks/owners, brief, proposal, timeline, open questions, risks; type/format/length/language under one expandable drawer, with context always inherited from Context Studio and optional per-mode override there. Existing H4/H5 review/export != generation implementation, preserve user docs/review.
- **Three-state rule on every setting**: `inherited / own override / one-shot temporary`; show effective target and status `pending / saved local / saved server / effective applied`. No hidden state transfer and no auto-save to a paid runtime from localStorage.
- **One action owner per function**: source selection Studio, answer provider Orchestrator, message editor/draft code, canonical room preference updater, instruction revision owner, H4/H5 documents, guarded dialogue scheduler (later). Parallel UI controls can *link* to that owner only.

### D3 staged execution
| ID | Delivery | Gate |
|---|---|---|
| D3.1 | Composer four equal triggers; direct modal navigation, no nested inspector; UI-only hide duplicate source selection; inline instruction name; hide redundant snapshot and boilerplate; SCSS tokens | Exact-head CI and owner QA dark/light; old H3 coverage tests not allowed to silently regress |
| D3.2 | Slim Beautify/draft modal to actual edit/preview/apply, previous outputs/history preserved; progressively move previous contextual task/review into Finalizer/document navigation, never duplicate source selection | Visual QA + draft no-loss/attachment/Undo/regeneration tests |
| D3.3 | Room settings compact icon presets, 1 room preference editor, clear account inheritance and immediate state; intro/help condensed; consent remains managed only in canonical owner with ACL | Multiple-user consent/room preference persistence + settings fallback tests |
| D3.4 | Context Studio selection resolution shared across Answer, Beautify optional, Finalizer, Auto Reply gated; remove hidden H3 selection markup and obsolete JS only after all providers/modes migrated and tests updated | Server-backed sets after backup, provenance, ACL versioning and old-source regression |
| D3.5 | Single category/type picker with icon chips for message/room/summary-document defaults, common reusable scheme and per-tool one-shot override; no duplicate tables; custom SDSelect | RU/EN/ES/HY, 360px/mobile, 200% zoom |
| D3.6 | Move remaining room/message settings into compact **composer-attached** sheet, eventually reducing permanent toolbar to 3–4 low-noise icons. Plan remains read-only, and source config always Studio | Native keyboard/focus, close/outside/escape, zero accidental Send, no loss of draft |
| D3.7 | **AI Super Input** (LAST, not implemented now): existing left sparkles next to mode switch toggles composer between Human/AI. In AI mode stronger Signal Deck treatment with visible ARIA status, no unexpected Send or provider request; user states a free-form task or asks to navigate/find users/work with already authorized app capabilities. Tool registry explicit scope, least-privilege, permitted action schemas, audit, per-action preview, user confirmation for irreversible/public/paid actions, budgets and kill switch. Server dispatch rechecks membership/ACL/consent, CSRF and authorization; no arbitrary model-generated shell/SQL, no secrets, no hidden browsing, no automatic sends. | S3/S6/S7 + S9 quality/cost/security gates and owner opt-in |

### Invariants and proof
- Removing a *duplicate UI* is not deleting underlying evidence/review and does not justify incorrectly telling user a function is fully migrated. UI-only hidden legacy markup is temporary and must be tracked as debt. Any test that formerly used a removed popup must be updated to the single canonical entrypoint and still exercise its safety assertion.
- New CSS should be imported after existing Signal Deck layers, use existing tokens, and honor reduced-motion, small screens and light theme; no new large library.
- Model status labels must be concise; the detailed no-provider/no-spend statement can remain an accessible title or help disclosure, but it should not occupy the primary UI.
- `db/schema.rb` owner local is modified; **never** reset/stash or run migrations without exact safe diff and backup. No real paid model, Railway or main merge until authorization.


## 12. D3.1a–D3.3 — Live status, standalone room instructions and Plan-shaped workspaces (owner review 22.11.2026)

**Source:** owner screenshots of `/rooms/3` at 00:03 and 00:10 after successful local ff-only to `3c7e784`, Yarn Classic JS/CSS builds and Docker restart; user confirmed direct Plan→Context transition works. Owner finding: the new toolbar lost the existing on/off states, Room/Message still feel like oversized legacy dialogs, room instructions need a dedicated Plan-like entry, and meaningful synthetic dialogue is required to assess context selection, semantics, prompt compilation and server contracts.

### A. Explicit effective state taxonomy — never infer that “available” means “enabled”

| State at composer | Source of truth | UI semantics | Direct action |
|---|---|---|---|
| Spelling hints | existing `ai-draft` room/local preference and `spellToggle.aria-checked` | **green on / red off**, modifies browser spellcheck for current author, NOT AI correction | delegates one click to actual switch; no second storage |
| My AI-history grant | server-backed `AiRoomContextConsent` via `ai-draft` smartReplyToggle | green only means **my personal consent**, not consent of all participants or an active model | opens canonical Room consent section, **no stealth PATCH** |
| Room-history eligible | server consent readiness already exposed as `data-ai-room-context-ready` | green only if server said `ready && available`; still no AI generation capability guarantee | opens canonical Room consent section |
| Auto Reply | existing locked auto-reply control | red / **unavailable** (not just off); don't claim active scheduler | opens explanation; cannot enable |
| Incoming translation | `incoming-translation` browser preference checkbox | green means setting enabled; **not** proof of supported local language model/pair | delegates to canonical checkbox `change` handler |
| Detailed chat display | `simple-chat` checkbox and browser preference | green on / red off; rendering only, no message/ACL changes | delegates to canonical checkbox `change` handler |

These **six** are the first confirmed status chips (`composer-settings-hub`), with green check / red X / amber pending. A status strip is separated from primary workspace buttons with spacing and a divider. Status proxies **never** own their own persisted state. AI Answer *mode selection*, “manual Grok available”, Room instruction revision number, effective context set count, and paid-provider availability are **not binary active toggles**: display those later as distinct non-green capability/metadata badges after auditing each authoritative source; never fabricate a total product-wide count from a room-only audit.

### B. Navigation / layered workspaces

- Primary visible actions now provisionally **five**: Context Studio, Plan (read-only), **Instructions**, Message/Beautify, Room. The separate Instructions trigger filters **the same** server-backed `room-ai-instructions` editor/revisions and local title/template library through `data-view=instructions`, not a duplicate form or source of truth.
- Message and Room native dialog sheets are styled as compact bottom workspaces patterned after Plan (animation, spacing, responsive width), preserving existing Stimulus targets, form data and tests. Transition closes an open Plan; no location reload and no Send on opening settings. Dialog close restores focus to invoking control.
- Status controls for reversible local settings call the original switch through its DOM action. Consent remains a separate, explicit server-side authorization.
- **Incomplete transition:** the old nested Room↔Message topbar and advanced legacy H3 content **are not yet empty or removed**; removing their DOM/controls now would break H3 tests and source-review security. D3.2/D3.3 must migrate the remaining actions/tests to the new canonical access path first, then leave the legacy shell inert and remove/retire it in a verified follow-on commit. Never claim old panels already emptied. No new backend preference tables, no migration, no paid calls, no merge or deployment.
- Preserve four locale versions RU/EN/ES/HY and Chrome 360px, dark/light, reduced motion, outside click, Escape, native focus return.

### C. D3.1a gates, then D3.2/D3.3

1. **Current D3.1a code gate**: exact-HEAD Baseline Rails + focused Chrome + locale/security/Docker/image, manual QA of **six** live states, new Instructions isolated view and 3 room/dialog transitions without lost draft. One previous Baseline at `3c7e784` had **172 Chrome / 2582 assertions / 1 intermittent H3 failure**, `AiContextualReplySystemTest#test_structured_preview_is_inert...`: Generate with Grok button unexpectedly disabled. Investigate if repeated; do not suppress an actual source/consent regression.
2. **D3.2**, only after gate: slim Beautify to single working copy, compact style picker, explicit Preview/Apply/Undo, no duplicate context editor. Gradually move old H3 tasks/review to its canonical document/Finalizer route; keep all provider cost/consent/ACL tests. When migration is proven, old Message modal's redundant sub-navigation may be retired.
3. **D3.3**, then: Room quick presets, canonical author scope, consent state, live status and instructions; move old room controls from duplicate legacy layout only after tests and authorizations are preserved. Runtime enable vs availability never conflated.
4. **D3.4** remains server selection adapter and explicit future browser-independent saved set sync; **D3.7** is last AI Super Input, not currently implemented.

### D. Synthetic data and joint acceptance

See `docs/QA_SEMANTIC_DIALOGUE_AI_PIPELINE_2026-11-22.md`: 14 chronological fake Jack/Eric messages with Rails 8, PostgreSQL POST /orders 422, tentative budget/deadline, obsolete scope and untrusted injected instructions. Contains no paid API operation or automatic Send. Evaluate: limited context versus full eligible history, own grant versus room readiness, latest incoming/participant/keywords/manual selection, truthful factual synthesis, override inheritance, one-message Beautify and separate Send, safe prompt-injection handling, dark/light/mobile/a11y. Owner evidence determines PASS/FAIL/PARTIAL, code CI alone does not.

**Status at authoring**: D3.1 initial owner QA `PARTIAL` (four buttons and Plan→Context accepted by screenshot; indicators absent). D3.1a `CODE_IN_PROGRESS / CI_PENDING / OWNER_QA_PENDING`; D3.2/D3.3 still `NOT_ACCEPTED`. Preserve local ` M db/schema.rb`.


## 13. 2026-11-22 — исполнительный план от D3.1b до MVP R1 (актуализация существующих S/T/D, НЕ замена контракта)

**Source/evidence (22.11.2026):** owner safely fast-forwarded local `f8c8cf4 → b52e614` on `feat/ai-answer-readiness-master-2026-11-20`; JS/CSS built inside Docker; web restart completed; local ` M db/schema.rb` remains untouched. Four actual Chrome screenshots at `/rooms/3` confirm desktop open/collapsed **Status** and **AI Settings** headers, Russian localized AI Plan values (Дружелюбно / Русский / Деловой / Комната), and standalone **Инструкции AI** sheet showing current revision 3. Screenshots alone do NOT establish smooth motion, retained unsent draft across dialogs, keyboard/Escape, any 390px/light mode, or all four locales. Exactly six Actions on **code HEAD b52e614** SUCCESS: Baseline 44959604368 (Rails 664/10821; full Chrome 179/2669, 0 fail/errors); focused 44959604576 (58/876); locale, security, Docker and image build all SUCCESS. These results do not automatically transfer to future documentation commits.

**MVP/R1 boundary:** user can use one coherent, secure room-centric application with human-controlled editable **AI Beautify** (own draft), consent-scoped **AI Answer**, source-backed editable/exportable **AI Finalizer** with default *Резюме беседы*, and an **AI Dialogue** policy with safe OFF/SUGGEST/DRY-RUN functionality; production **automatic Send OFF** unless an independent S7 authorization, safety and owner-approval gate is explicitly passed. Production provider spend bounded and attributed to real Postgres ledger, one verified context contract with full *eligible candidate inventory* (NOT a promise to pass whole history), RU/EN/HY/ES UI, responsive and backup/restore. R0 isolated deploy is not R1 approved production. Full automation/AI Super Input and S10 monetization are separate post-MVP releases unless owner later explicitly changes the scope.

**Critical execution sequence (existing IDs preserved; each milestone requires exact HEAD CI + browser QA):**

| Gate | Existing IDs | Deliverable, actual closure criteria | Current proof / dependency |
|---|---|---|---|
| G0 current | D3.1/D3.1a/D3.1b, T1.3, S1.3, D7 | Finish owner B1–B4: six true states; two independently folded aligned bars; RU plan; *Instructions AI* same revision owner; no-draft-loss/Send; Plan→Message/Room/Instructions; Escape/outside/focus; light/dark, 390×844 and RU/EN/HY/ES; 200% zoom/reduced-motion | **CODE_CI_GREEN / OWNER_DESKTOP_QA_PARTIAL**, NOT ACCEPTED |
| G1 safety | S0.1–S0.4, M33/M34, D5 | Confirm Context Studio select→Apply→persist→reload→revoke→recheck; inspect owner `db/schema.rb` diff; local PG/media backup and **isolated restore** before any migrations/server-set tables; inventory actual code/test versions and preserve data | S0.2 **BLOCKED** until safe owner evidence; can run independent non-DB UI work meanwhile |
| G2 composer | D3.2, S1.1/S1.3, D3 | Slim Message/Beautify to **one working draft** and compact preset/style, manual preview→apply→undo; preserve original draft, attachments, generated candidate, separate Send; move older H3 draft/coverage/review routes to canonical owners *before* removing any legacy markup/tests | **NOT STARTED**; no duplicate source picker |
| G3 room settings | D3.3, S2.1/S2.2 | Compact Room/profile presets; explicit system→account→room inheritance, server sync, revisioned instructions + local template names; consent and personal grant state accurate, no automatic PATCH; delete duplicate visible controls only with test replacement | **NOT STARTED**; stay with existing `AiRoomWritingPreference` and revision service |
| G4 one effective plan | T1/T1.3/T4 prerequisite, S2.3–S2.5, S3.1 | Reconcile mode override versus common defaults, one-shot values, origin + diff, protected server policy, error/failure feedback. Audit existing Orchestrator/InputContract and related services, make a single deterministic compile contract; no second preference store | **PARTIAL**; do not introduce new schema without G1 |
| G5 production-cost safety, then first real Answer | S6.1–S6.5, T2, S3.2–S3.5 | Verify CURRENT provider model/price/privacy/retention; explicit per-request cost authorization, max reservation, atomic PG settlement/reconciliation, idempotency/timeout/rate+tenant caps/kill switch/log redaction; then **only with owner approval** 1 synthetic private-room Answer call, unanimous consent, actual ledger settlement and **no automatic Send**; verify factual boundaries | **BLOCKED** for live spend until consent/cost/provider review. Existing Answer path dev-gated/bounded and PG ledger partial |
| G6 contextual Beautify | T3, S3 | Migrate Beautify from separate LocalBudgetLedger into same validated engine/PG accounting; own-draft-only continues with no room-history grant; optional context only through approved Context Studio scope; editable candidate/undo; no invented facts and no Send | **NOT DONE**, model integration gated |
| G7 modifier/script | T4, S2.4, D3.5 | One catalog of tone/length/format/emoji/presets and versioned reusable scripts/templates with per-mode override and one-shot reset; proposal/preview/diff/undo; optional AI-assisted modification requires separate user approval + billing | **PARTIAL/SPEC**; reuse canonical templates/revisions |
| G8 server context | T5, D3.4, D5, S3.3/S3.4, S8.1/S8.5 | Browser-independent named saved context sets only after G1 backup/migration review; full paginated *eligible inventory*, text/author/date filters, manual selected ID+version/ACL/consent fingerprint, source-backed data contract, stale edit/delete/revoke handling, target auto replacement; Context Studio only picker for Answer, optional Beautify, Finalizer and gated Dialogue | **PARTIAL**: browser-local sets only; current Answer max 240 candidate / 9 excerpts / 2400 chars and not full history |
| G9 interface convergence | D3.5/D3.6, D4/D6/D7 | Single task-sheet settings vocabulary; remove obsolete H3 navigation only after transport and ACL tests migrated; exhaustive four-locale strings incl errors, display 320/360/390/430/600/768/1024/1440/1920 + 200% zoom, keyboard/screen reader/reduced-motion, dark/light/system, no losses | **PARTIAL**; cross-cutting in parallel with G4–G8 and must pass before R1 |
| G10 multilingual, knowledge and Finalizer | T6, S4/S5/S8 | Truthful browser translation + unsupported-pair fallback; network translation only per-user grant/cost. After storage audit, safe TXT/MD/CSV/PDF knowledge ingestion with ACL/chunks/citations, no prompt-as-authority. Real AI Finalizer: default **Резюме беседы** + decisions/tasks/questions/risks/brief; source-backed evidence, editable named versions, actual supported MD/TXT/PDF exports, explicit paid action, no auto-send | **PARTIAL/SPEC**; existing H4/H5 export/review does **not** count as Finalizer generation |
| G11 AI Dialogue safe lane | T7, S7 | OFF default, SUGGEST/DRY-RUN test, policy allowed topics/hours/cooldown/limits, worker/run journal/idempotency/kill switch, no bot loops; readiness is configuration completeness not truth; **AUTO Send requires additional independent owner consent/safety gate** and may remain OFF in R1 | **NOT ACCEPTED**, experimental S7 branch not production |
| G12 deploy and release | T8, S9, remaining S0, D7 | Isolated Railway R0 synthetic users PG+Redis+durable media HTTPS/WSS, verified backup/restore, CSP/ACL/security/observability, bounded spend and rollback; failure matrix revoked grant/stale version/outage/concurrency/unsupported language. R1 production-approved exact SHA, real user E2E and owner sign-off | **NOT DEPLOYED / RELEASE BLOCKED** |

**Post-R1 (not falsely included in core MVP):** `D3.7` AI Super Input with scoped tools, preview and confirmations only **LAST** after S3/S6/S7/S9 gates; `S10` integrations, tenant API/widget and paid commercial pilot/revenue validation after R1, with separate KYC/legal/usable-funds validation. Do not auto-merge or auto-deploy.

**Safety and proof required for every G gate:** exact current SHA GitHub 6 checks (Rails, complete two-browser Chrome, focused Chrome, YAML integrity, Security, Docker/image), manual owner screenshot and action checklist `PASS/PARTIAL/FAIL/NOT_TESTED + P0/P1/P2`, two-user ACL + explicit consent/revoke + stale revision, original draft/attachments preserved and separate Send, no paid API or message unless owner authorizes. Existing QA dataset `docs/QA_SEMANTIC_DIALOGUE_AI_PIPELINE_2026-11-22.md` (14 fake Jack/Eric messages, separate local room, unapproved $1,200/Friday and HTTP 422, injection) is a manual input specification, not yet seeded or AI-tested. No time estimates or progress percentages inferred from completed code check counts.

**Immediate actions (1–3 only):** (1) record G0 desktop evidence and inspect 390px/light + closing/reopening **without Send**; (2) confirm instructions/Plan→Message/Room retains a temporary unsent draft; (3) when G0 closes, implement G2 D3.2 in a minimal feature commit and rerun exact-head CI. Keep ` M db/schema.rb` untouched until G1.

## 14. 2026-11-24 — решение владельца: независимый персональный AI, общие room defaults без голосования

**Нормативное дополнение к §§2,3,11–13 и roadmap issue #15; прежние утверждения про обязательное единогласное включение AI на уровне комнаты заменены этим контрактом.** Полный ADR: [ADR_PERSONAL_AI_ROOM_DEFAULTS_AND_MESSAGE_ORIGIN_2026-11-24.md](ADR_PERSONAL_AI_ROOM_DEFAULTS_AND_MESSAGE_ORIGIN_2026-11-24.md).

- Каждый участник, включая создателя, имеет свой независимый набор настроек и одинаковые AI-инструменты. Управление участниками и общими defaults принадлежит создателю комнаты; персональные установки не дают прав менять чужие данные и наоборот.
- Default комнаты, явно заданный создателем, наследуется каждым без отдельного копирования; личный override имеет приоритет и сохраняется при изменении default. Изменения автора «для себя» не меняют общий default.
- Убрать модалки коллективного согласования. **Не** путать их удаление с автоматическим разрешением отправлять историю других авторов модели. Отдельные revocable author grants, ACL, источник, fingerprint, бюджет, отправка и runtime gate остаются обязательными.
- В AI Answer/Finalizer внешнему провайдеру допустимы только сообщения авторов с актуальным индивидуальным разрешением; без пригодного incoming контекста показывать честный blocker, не выключать персональный Beautify.
- Каждое сообщение должно иметь честный persisted origin: ручное / улучшенное AI / сгенерированное AI; прежний boolean `ai_assisted` не позволяет отличить последние два случая для исторических сообщений, поэтому их подтип не придумывать.
- **Реализация на дату решения не закончена**: текущий `RoomContextAccess` ещё требует unanimity; `ContextAuthorPolicy` — только read-only foundation и не используется провайдером. Не объявлять новую модель активной до полной source-permission migration и нового test matrix.
- G1 backup/restore до миграций. PR #18 source reauthorization, PR #19 UI, PR #20 membership refresh остаются отдельными Draft; локальный `db/schema.rb` владельца не переписывать, Railway/production не трогать без согласованного gate.

**Новый порядок:** PR #20 owner QA → независимый author-grant foundation + tests → реальный source filtering со сквозным reauthorization → persisted owner-shared defaults + personal overrides → message origin verification → retire voting modal → двухбраузерная acceptance и отдельный релиз. Доказательства/ссылки — в LIVE_STATUS.
