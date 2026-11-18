# TURBO CHAT / RELAY WORKSPACE — MASTER HANDOFF ДО ФИНАЛЬНОГО РЕЛИЗА

**Версия:** 3.0 · **Дата фактического checkpoint:** 09.11.2026 · **Язык исполнения:** русский  
**Назначение:** единственный стартовый мастер для следующего чата-разработчика в проекте CAREER.  
**Проект:** существующий Ruby on Rails-мессенджер **Turbo Chat**; стратегическое направление — **Relay Workspace / AI-native Client Communication & Content Collaboration**.  
**Источник текущего состояния:** GitHub-код/PR/CI + последний вывод терминала Linux Mint + последний скриншот владельца.  
**Критическое правило:** старые мастера с HEAD `15f1bf2`, `990ea69` и задачей «начать H1/H2.1» **устарели**. Не повторять уже завершённые этапы.

> **НОВОМУ ЧАТУ: НАЧНИ С H2.5, А НЕ С AI И НЕ С ПЕРЕПИСЫВАНИЯ ПРИЛОЖЕНИЯ.** Владелец 09.11.2026 визуально принял авторизованную главную страницу H2.4, но указал на отсутствие фирменного favicon и стандартные Rails-страницы 404/422/500. Их надо завершить и локально принять **до дальнейших крупных изменений**. Подтверди текущий HEAD/CI, затем реализуй H2.5 в **той же ветке и Draft PR #2**; не затрагивай локально изменённый `db/schema.rb`, сообщения, media, volumes и production. После H2.5 продолжай по этапам ниже вплоть до безопасного коммерческого релиза; не включай настоящий AI без отдельных согласий владельца на provider, передачу данных, бюджет и миграции.

---

## 0. Исполнительный контракт и полномочия

Роль нового чата: lead Rails engineer + technical product owner + UX/accessibility lead + privacy/security reviewer + QA/release manager. Результат оценивается не количеством коммитов и экранов, а **работающим, воспроизводимым, безопасным продуктом**, который со временем приносит проверенную коммерческую пользу.

**Разрешено в существующем Draft PR #2:** изучать код и документацию; проектировать небольшие проверяемые изменения; добавлять собственные assets, ERB, SCSS, Stimulus, тесты, ADR/checkpoints; устранять доказанные регрессии; проверять точный SHA в GitHub Actions; давать владельцу 1–3 инструкции по локальной приёмке.

**Отдельное согласование до выполнения:** merge в `main`, force-push, перемещение/удаление ветки, новые БД-миграции на локальной или production БД, изменение/удаление volumes и реальных файлов, создание/обновление Railway staging/production, подключение облачного storage, внешних AI-провайдеров, любые платные API/счета, данные пользователей внешним LLM, внешние интеграции с записью, публичная публикация, тарифы и приём платежей.

**Не делать:** `git reset --hard`, `git restore db/schema.rb`, `git clean -fd`, `db:reset`, `db:schema:load`, `docker compose down -v`, удаление `storage/`, force-push, фиктивный AI-output, фиктивное `AI ON`/`AUTO ON`, сброс тестовых сообщений Jack/Eric, публикацию demo-данных как клиентских, заявление об E2EE без фактического протокола. Не запрашивать токены, пароли, API keys или дампы приватных сообщений.

**Алгоритм работы:** проверенные факты → маленький scope → реализация → регрессия/ACL/a11y тесты → git commit SHA → Rails/Redis/ActionCable/Chrome/Security/Docker **на этом SHA** → локальный screenshot/CLI владельца → явная приёмка → checkpoint. Глобальные UI-редизайны без узкой задачи и массовое переписывание на Vue запрещены.

---

## 1. Точная точка продолжения — 09.11.2026

| Параметр | Проверенный статус |
|---|---|
| Репозиторий | <https://github.com/TheGor-365/turbo_chat> |
| Рабочая ветка | `feat/security-baseline-2026-11-03` |
| Текущий PR | <https://github.com/TheGor-365/turbo_chat/pull/2> — **OPEN / DRAFT**, не merged |
| **Последний подтверждённый HEAD** | **`4d3ff993fc85837e7c3e429412c723cf41d8f63c`**, короткий `4d3ff99` |
| Rails/Redis/Cable/Chrome | <https://github.com/TheGor-365/turbo_chat/actions/runs/42687991266> — PASS |
| Security audit | <https://github.com/TheGor-365/turbo_chat/actions/runs/42687990790> — PASS |
| Docker smoke | <https://github.com/TheGor-365/turbo_chat/actions/runs/42687991045> — PASS |
| Rails | **274 tests / 2001 assertions / 0 failures / 0 errors / 3 прежних skips** |
| Redis / cross-process ActionCable | **2/6** и **1/5**, PASS |
| Chrome/Selenium | **74 tests / 1115 assertions / 0 failures/errors/skips** |
| Checkpoint PR | <https://github.com/TheGor-365/turbo_chat/pull/2#issuecomment-6750006159> |
| Локальная ОС | Linux Mint; рабочий каталог существующего `turbo_chat` (сначала `pwd`, не придумывать абсолютный путь) |
| Локальный сервер | <http://127.0.0.1:3000/> |
| Последний локальный git | **Fast-forward `13d56f4..4d3ff99`**, `git rev-parse --short HEAD` → `4d3ff99` |
| Последний локальный Docker | `docker compose up -d --build` успешно, web recreated, PostgreSQL и Redis `Healthy` |
| **Локальное отклонение** | **`M db/schema.rb` — намеренное, сохраняется; не сбрасывать/перезаписывать** |
| Последний screenshot владельца | Авторизованная Home Jack: `Pick up where you left off`, 0 unread alerts, Eric, Project Circle, Quick actions; **владелец сказал «отлично»** |
| Последняя явная директива | **Сначала фирменный favicon + брендированные страницы 404/422/500; затем остальные серьёзные этапы. Подготовить этот master handoff** |

### 1.1 Что именно подтверждено последней локальной приёмкой

- На `/` авторизованный Jack видит готовый Home в стиле Signal Deck, контекстные CTA, именно Eric/Project Circle, 0 непрочитанных уведомлений. Это **визуально принято владельцем 09.11.2026**. Не путать с доказательством коммерческой готовности.
- Последний терминальный вывод показывает `git status -sb` с `M db/schema.rb`, корректный fast-forward, успешную сборку Web и здоровые db/redis. Это локальный Docker, **не Railway production**.
- На вкладке браузера значок **не фирменный / выглядит чужеродно**: нельзя считать favicon реализованным только потому, что файлы в `public/` существуют. В `app/views/layouts/application.html.erb` **нет явных link-тегов favicon/touch**.
- Файлы `public/404.html`, `public/422.html`, `public/500.html` **есть**, но содержат стандартный светло-серый Rails шаблон; брендированного fallback нет.
- Гостевая Home и guest login после H2.4 **покрыты CI**, но **не подтверждены новым скриншотом владельца**. H2.3 профиль принят по desktop, полная ручная проверка мобильной страницы и reset email остаётся в общей release-матрице.

### 1.2 Приоритет источников истины

1. Свежий GitHub head в **этой ветке**, PR state, CI на точном SHA.
2. Текущий пользовательский локальный `git status`, Docker health, screenshots и явные решения владельца.
3. Актуальные исходники, тесты и ADR; затем этот мастер.
4. Старые чекпоинты и исторические мастер-планы — как справка, **не как актуальный next step**.

Новый чат не должен утверждать, что знает локальную БД, filesystem или пользовательский экран без текущего лога/скриншота. Чаты не синхронизируются автоматически. Временная метка и SHAs подтверждают историческую точку, но HEAD надо снова проверить при старте.

---

## 2. Стек, реальные возможности и границы безопасности

### 2.1 Реальный стек

- **Ruby `3.4.12`**, **Rails 8.1.x** (README фиксирует Rails 8.1.4; Gemfile требует `>= 8.1.4.1`, фактическую lock-версию проверять по `Gemfile.lock`); PostgreSQL; Redis 7.
- Rails-first архитектура: ERB, Hotwire Turbo, Stimulus, Active Record, Active Storage, ActionCable, Devise, Pagy, Sass, Bootstrap как legacy-слой, **Signal Deck / Quiet Canvas** как основной визуальный язык.
- Docker Compose на Linux Mint (`Dockerfile.dev`), Node 24 и Yarn Classic `1.22.22` в текущей сборке; GitHub Actions Rails/Chrome/Security/Docker.
- Demo-пользователи **Jack** и **Eric**, пользовательский контент локально. Не удалять и не публиковать приватное содержимое.
- Репозиторий — образовательный/портфолио development build, **публичный production не принят**.

### 2.2 Уже реализовано — не переписывать

- Devise sign-up / sign-in / password reset / profile name/avatar/email/password (смена учётных данных требует `current_password`), presence privacy `PATCH /account/presence`; отображение имени без утечки login email.
- DMs, public rooms (join/leave), private groups, invitations/member/owner permissions, текущие membership ACL.
- Переписка, real-time ActionCable через Redis, replies, edit/delete, reactions, typing/presence TTL, явная невидимость, single source of truth HTTP reconnect/room sync, read-state/unread.
- Медиасообщения: изображения/вложения/voice/video preview/playback, ActiveStorage private read ACL, upload safety and size limits, сохранение черновика; диапазонный playback, камеры и browser MediaRecorder — смотреть точные checkpoint-ограничения, не объявлять каждый носитель окончательно QA-accepted.
- Activity & History `/notifications`: поиск по тексту и именам разрешённых файлов, filters `Conversation`, `When`, category chips, ограничения на текущие memberships, ссылки в сообщения; две одинаковые borderless панели auto-GET фильтров (**H2.2b**).
- Собственная Signal Deck система: sidebar, controls, nav, light/dark/system, mobile drawer, безопасные SVG через `sd_icon`.
- AI **только offline**: `AiWorkspace` scope/review/current room preview, 6 immutable presets, локальное редактирование собственного черновика, Apply/Undo/manual Send, room-local browser settings, native spellcheck. **Нет реального provider inference и no outbound LLM**.
- P0 read-only исправление `GET /`: посещение Home **не меняет** `User.status`, что проверено request и browser regression.
- Локальный backup + проверка archive checksum и изолированный restore drill **в историческом checkpoint**; это **не означает**, что новый production backup уже работает.

### 2.3 Состояние AI — четыре важных «НЕТ»

1. **Нет реального AI API/provider**; `Gateway.configured?` fail-closed и `generate!` запрещён.
2. **Нет согласованного durable consent** на передачу пользовательских/чужих сообщений модели.
3. **Нет действующего AI budget/billing** и утверждённого лимита расходов.
4. **Нет права автоматически обрабатывать историю, сообщения участников, вложения, Gmail/Drive либо auto-send**.

Существующий `docs/ADR/2026-11-09_AI_CONSENT_BUDGET_PROVIDER_READINESS.md` — **проект контракта H1/Gate 2B.6**, не законное согласие и не работающая система. Написан и покрыт отрицательными тестами, **H1 повторно не начинать**.

### 2.4 Реальный остаточный риск

- **Устаревшие assets favicon / статические ошибки:** H2.5 — immediate priority.
- Три старых Rails skips в CI — обоснованно исследовать до релиза, не маскировать.
- Linux Mint физический микрофон/ALSA/PipeWire: у владельца раньше записывался шум, речь не была разборчивой. **Отложено владельцем до финального QA**. Перед релизом проверить OS/браузер, не путать с уже работающим транспортом voice.
- Не доказаны production backup/restore, внешняя email delivery, HTTPS/WSS/reconnection под нагрузкой, data retention/deletion и реальные коммерческие платежи.
- Все последние зелёные тесты — на конкретном SHA в тестовой среде, не на публичном релизе.

---

## 3. Журнал этапов: что сделано, что принято, что дальше

| Gate | Реализация и источник | Статус |
|---|---|---|
| Security/Realtime/Core, 04–08.11 | Rails messenger, Redis, membership ACL, files, search, activity, unread, rooms, reactions, presence и другие checkpoint из `docs/` | **В коде и подтверждено CI/локальными итерациями**, полноценный release QA впереди |
| Gate 2A, 2B.0–2B.1 | Offline `AiWorkspace` review, source selection, preset registry, security denial tests | **Код/CI**, selected-history preview owner reviewed; **не реальный AI** |
| Gate 2B.2–2B.5 | Composer-adjacent Edit draft / Room settings, preferences, statuses, Apply/Undo | **Код/CI**, desktop review и локальные скриншоты |
| **H1/Gate 2B.6** | ADR consent, privacy, budget, provider readiness + negative tests; commit history до `5953901` | **Проектная готовность без реализации provider/consent tables** |
| **H2.1b** | Компактные Edit draft/Room settings, sidebar colors/icons, меньше текста, no unnecessary scrollbar, без внешнего border | **CI green; владелец принял desktop** |
| **H2.2b** | Одинаковые Conversation/When, automatic GET refresh + keyboard/ARIA/mobile | **CI green; владелец принял визуально и перешёл дальше** |
| **H2.3** | Devise Profile/Security/Presence/Notifications/Removal, Login/Signup/Reset, responsive design | **CI green `13d56f4`, desktop profile owner accepted**; отдельный гостевой визуальный review не подтверждён |
| **H2.4** | Настоящий authorized/guest Home, no private snippets, no fake stats, action links | **CI green `4d3ff99`, signed-in Home owner accepted** |
| **H2.5** | **Фирменный favicon/touch + статические 404/422/500** | **НЕ НАЧАТО; самый первый этап нового чата** |
| H2.6 | Finishing accessibility, screens/states/guest QA, brand/error audit | ПЛАН, после H2.5 |
| H3 | Первый настоящий opt-in own-draft AI with real provider, budgets, privacy, migration | **ЗАПРЕЩЁН до отдельных approvals** |
| H4 | Scoped conversation context, consent member matrix, summaries/citations | ПЛАН, после H3 |
| H5 | Conversation→Brief/Deliverable, versions, approvals, exports, validation | ПЛАН, ключевая коммерческая ценность |
| H6 | Teams, clients, permissions, limited integrations, automation, public API | ПЛАН, только по спросу |
| H7 | Hardening, privacy, QA, restore, mobile, accessibility, reliability | ПЛАН/непрерывные slices и финальный gate |
| H8 | Staging → release candidate → production/legal/billing → pilots/public launch | ПЛАН, только после одобрений |

**Важно:** код/CI → локально просмотрено → принято владельцем → production verified — разные состояния. Не отмечай весь H2/UI как release-ready только из-за принятого desktop Home.

---

## 4. Прямая карта исходников и документации

### 4.1 Точки входа

| Задача | Файлы |
|---|---|
| Роутинг | `config/routes.rb` (`root 'pages#home'`, Devise routes, rooms, notifications) |
| Общий HTML head и navbar | `app/views/layouts/application.html.erb`, `app/views/layouts/_nav.html.erb` |
| Главная H2.4 | `app/controllers/pages_controller.rb`, `app/views/pages/home.html.erb`, `app/assets/stylesheets/signal_deck_home.scss` |
| Главная test | `test/controllers/pages_controller_test.rb`, `test/system/home_signal_deck_system_test.rb` |
| Профиль и auth | `app/views/devise/registrations/{new,edit}.html.erb`, `devise/sessions/new.html.erb`, `devise/passwords/{new,edit}.html.erb`, `app/assets/stylesheets/signal_deck_account.scss` |
| App CSS entry | `app/assets/stylesheets/application.bootstrap.scss`, imports `signal_deck`, `signal_deck_refinement`, `signal_deck_workspace_v2`, `ai_workspace`, `signal_deck_account`, `signal_deck_home` |
| First-party icon helper | `app/helpers/signal_deck_helper.rb` (`sd_icon`, allowlist `ICONS`) |
| Общая UI система | `app/assets/stylesheets/signal_deck.css`, `signal_deck_refinement.css`, `signal_deck_workspace_v2.scss` |
| Room, inbox, activity | `app/controllers/rooms_controller.rb`, `notifications_controller.rb`, `app/views/rooms`, `app/views/notifications` |
| AI | `app/services/ai_workspace/`, `app/javascript/controllers/ai_*`, `config/ai_workspace/presets.yml`, `docs/ADR/2026-11-09_AI_*` |
| Настоящие текущие favicon placeholders | `public/favicon.ico`, `public/apple-touch-icon.png`, `public/apple-touch-icon-precomposed.png` |
| Настоящие текущие технические страницы | `public/404.html`, `public/422.html`, `public/500.html` |
| GitHub CI | `.github/workflows/` и `test/` |
| Защита и release | `docs/SECURITY.md`, `docs/THREAT_MODEL.md`, `docs/RELEASE_CHECKLIST.md`, `docs/P1_LOCAL_BACKUP_AND_RESTORE_RUNBOOK.md` |

### 4.2 Обязательные документы для следующего чата

- [Дизайн Signal Deck](https://github.com/TheGor-365/turbo_chat/blob/feat/security-baseline-2026-11-03/docs/SIGNAL_DECK_DESIGN_SYSTEM_V1.md) — palette, spacing, tokens, interaction.
- [UI/UX backlog 09.11](https://github.com/TheGor-365/turbo_chat/blob/feat/security-baseline-2026-11-03/docs/UI_UX_BACKLOG_2026-11-09_OWNER_REVIEW.md) — **исторический план**, в нём Home/Account/Filters могут всё ещё помечаться pending; исправлять статус по current SHA.
- [AI readiness ADR](https://github.com/TheGor-365/turbo_chat/blob/feat/security-baseline-2026-11-03/docs/ADR/2026-11-09_AI_CONSENT_BUDGET_PROVIDER_READINESS.md) — offline security contract, не разрешение real AI.
- [AI Content Engine contract](https://github.com/TheGor-365/turbo_chat/blob/feat/security-baseline-2026-11-03/docs/ADR/2026-11-09_AI_CONTENT_ENGINE_CONTRACT.md).
- [Execution roadmap](https://github.com/TheGor-365/turbo_chat/blob/feat/security-baseline-2026-11-03/docs/EXECUTION_ROADMAP_2026-11-04.md).
- [Product capabilities roadmap](https://github.com/TheGor-365/turbo_chat/blob/feat/security-baseline-2026-11-03/docs/PRODUCT_CAPABILITIES_ROADMAP_2026-11-04.md).
- [Local development](https://github.com/TheGor-365/turbo_chat/blob/feat/security-baseline-2026-11-03/docs/LOCAL_DEVELOPMENT_RU.md).
- [Release checklist](https://github.com/TheGor-365/turbo_chat/blob/feat/security-baseline-2026-11-03/docs/RELEASE_CHECKLIST.md).
- [Backup/restore runbook](https://github.com/TheGor-365/turbo_chat/blob/feat/security-baseline-2026-11-03/docs/P1_LOCAL_BACKUP_AND_RESTORE_RUNBOOK.md).
- [Текущий PR #2 с полными checkpoints](https://github.com/TheGor-365/turbo_chat/pull/2).

**Исторический большой мастер**: `TURBO_CHAT_AI_NATIVE_MASTER_HANDOFF_2026-11-09(1).md`, ранее предоставленный пользователем (около 100 KB), содержит расширенную продуктовую IA и H0–H8; его current HEAD `15f1bf2` и инструкции «сделать H1/H2.1» теперь **НЕАКТУАЛЬНЫ**. Новому чату сначала использовать **этот v3.0**.

---

## 5. ПЕРВАЯ ЗАДАЧА НОВОГО ЧАТА — H2.5 / D0.2 BRAND + ERROR PAGES

### 5.0 Бизнес-результат H2.5

Пользователь видит собственный узнаваемый значок Turbo Chat в Chrome/tab/bookmark/mobile; технические ошибки выглядят как часть Signal Deck и сообщают о реальной проблеме, даже когда Rails приложение аварийно недоступно. **Никакого визуального копирования другой марки. Никаких новых функций AI/миграций.**

### 5.1 Read-only аудит, выполнить ПЕРЕД правкой

1. Через GitHub connector подтвердить HEAD PR #2 и успешность exact SHA CI; проверить `app/views/layouts/application.html.erb`, `app/helpers/signal_deck_helper.rb`, `public/favicon.ico`, `public/apple-touch-icon*`, `public/404.html`, `422.html`, `500.html`, build/lint pipeline, тесты.
2. Сверить текущий бренд: существующая навигационная пиктограмма — оригинальная **пузырь-диалога в фиолетовой квадратной плашке**; ее first-party `sd_icon("messages")` и styling `sd-brand__mark` использовать как основу дизайна. Не подменять случайным логотипом/стоковой иконкой. Для тонких пиксельных размеров проще вариант без слов.
3. Зафиксировать матрицу icon formats и поведение в браузере: существующие `.ico` и touch PNG есть, но generic / legacy; HTML layout без явных icon links. Тест favicon по имени файла **недостаточен**.

### 5.2 Favicon — строго пошаговая спецификация

**Подзадача A — assets (реальные файлы, не только изображение в чате)**

- Сделать **собственный минималистичный** знак, согласованный с верхним левым `Turbo Chat`: насыщенная фиолетовая подложка с белым контуром диалога/сообщения; достаточно контрастный в dark и light, читаемый на 16×16.
- Добавить/заменить соответствующие реальные иконки: `public/favicon.svg` (основной формат при поддержке браузером), `public/favicon.ico` с размерами 16/32 (или больше, если оправдано), `public/apple-touch-icon.png` 180×180. Для `apple-touch-icon-precomposed.png` сохранить смысл старого пути / сделать такой же брендированный вариант при необходимости. Не удалять старые файлы до проверки всех ссылок.
- Размеры, прозрачность, MIME и фактический raster-content проверить программно. Не «перекрасить» словами в документации: нужно создать настоящий файл и увидеть его в tab.
- Если позже будет manifest/PWA, это отдельный пункт: **не обещать installable PWA, если нет manifest/service worker/offline handling**.

**Подзадача B — HTML wiring**

- В `app/views/layouts/application.html.erb` явно указать корректные favicon/touch `<link>` (в безопасной Rails-подстановке или versioned public path) для браузеров с SVG и ICO fallback. Проверить `rel`, `type`, `sizes` и обслуживание из `public/`.
- Учесть агрессивный кеш favicon Chrome: сравнить actual assets и после локального rebuild проверить новую вкладку/инкогнито, а не объявлять код ошибочным из-за старого кэша. Не менять глобальный CSRF/CSP ради favicon.
- Убедиться, что при guest/auth/rooms/Home и в light/dark таб использует **один и тот же** бренд.

**Acceptance favicon:** на локальном owner screenshot таб использует узнаваемый Turbo Chat icon; network requests `.svg`/`.ico` возвращают ожидаемые файлы и MIME/HTTP; мобильный touch-icon реально брендирован; нет обращения к сторонним CDN.

### 5.3 Статические 404/422/500 — требования

- Заменить только содержимое `public/404.html`, `public/422.html`, `public/500.html` на **самодостаточные** HTML5-страницы Signal Deck: фирменный знак встроенным inline SVG, единые семантические CSS-токены/цвета, контрастная типографика, спокойная поверхность без грубой рамки.
- **САМОЕ ВАЖНОЕ:** Rails может не работать. Поэтому **нет ERB, ActiveRecord, JavaScript dependencies, CDN, asset pipeline, Bootstrap или ссылок на CSS, которые требуют работающего Rails**. CSS и inline SVG прямо внутри каждого HTML, никаких пользовательских данных или stack traces.
- Текст: `404 — Page not found` / `422 — Your request could not be completed` / `500 — Something went wrong`. 404 — проверить URL или вернуться домой; 422 — безопасная формулировка о непринятом изменении, без обвинения пользователя; 500 — нейтральная ошибка сервера, без сообщения об учётных данных, без фиктивной кнопки support.
- Рабочая ссылка `Home` → `/` (изолированный HTML link; при 500 может временно не работать, это честно, не обещать устранение сбоя). Вторичный текст `Try again later` только для 500. Не делать misleading авторизационные сообщения.
- Проставить `<meta name="viewport">`, readable `<title>... · Turbo Chat</title>`, `lang="en"` (проект пока англоязычный), встроенный SVG `role="img"`/a11y label либо decorative + текстовый бренд; системные шрифты; мобильная ширина 320px.
- Можно поддержать automatic dark/light через `prefers-color-scheme`, но без JS-theme localStorage: static error fallback нельзя привязывать к Rails / Stimulus. Контраст и reduced motion проверить.
- Точно **не** внедрять `rescue_from StandardError` с рендером 200, не переназначать статусы и не менять security handling.

**Acceptance errors:** самостоятельное открытие `.html` (проверка CSS/visually) и production-like проверка фактического HTTP **404 / 422 / 500**, когда ошибка обслуживается этим файлом. В development Rails часто показывает debug exception page: это **не доказательство**, что статические fallback отсутствуют; использовать корректную изолированную тестовую среду, избегая изменений основного production. Скан: нет trace/password/email/token, исходные HTTP статусы не изменены, ссылки и responsive работают.

### 5.4 Тесты H2.5

- Request/HTML test наличия icon links в `layout`, отсутствия внешних обращений и корректных путей.
- File assertions реального PNG/ICO/SVG, sizes, отсутствие пустых placeholders, читаемость SVG/корректный format; не полагаться на имя `favicon.ico`.
- Static pages test как файлы: `<html lang>`, meta viewport, текстовая идентификация 404/422/500, self-contained CSS, никакого ERB/external JS/font/CDN, отсутствие секретов/traces.
- Прогон во всех типах страницы: guest home, sign-in, signed-in home, room. Selenium screenshot хотя бы desktop + mobile 390 для fallback через безопасную isolated preview.
- Проверить response status в production-like или test harness, не подменяя main Rails routes и не создавая фиктивные catch-all 200.
- Полный exact-head CI Rails/Redis/Chrome/Security/Docker **PASS**, затем пользовательский скриншот (tab icon + одна error page); критерий пользователя — «узнаваемый брендинг и не дефолтный Rails».

### 5.5 Предлагаемые атомарные коммиты H2.5

1. `H2.5a: first-party icon assets and explicit layout favicon links` + проверки asset/content.
2. `H2.5b: standalone Signal Deck 404/422/500 fallbacks and tests`.
3. `H2.5c: fix only evidence-backed CI/browser defects`, checkpoint + owner acceptance.

**H2.5 не завершён, пока владелец не увидит результат в браузере.** Не менять app logo везде без причины; согласовать визуальную преемственность с уже принятым Signal Deck. `main` не трогать.

---

## 6. H2.6 — завершение фундаментального UX/доступности ДО большого AI

После H2.5 и owner-приёмки:

1. Просмотреть гостевые Home/Sign up/Log in/Reset, профиль и error pages в dark/light/system. Guest Home нового H2.4 CI green, но пользовательский screenshot отдельно не получен.
2. Проверить реальные состояния: empty account, ошибки валидации, invalid password, подтверждение удаления, permission denied, media unsupported, reconnect/offline, pending invite, no results, loading/disabled, dismissed toast.
3. Один компонент — одна семантика: `sd_icon` + aria-label/title; минимальные borders, reading order, native forms, focus-visible; продолжить унификацию legacy dropdowns только при явном UX-дефекте. Никаких неработающих «настроек».
4. 320/390/768/1024/1440 px, viewport высота ~640, zoom200%, reduced motion, keyboard-only Tab/Enter/Escape, touch, screen-reader labels, контраст WCAG 2.2 AA, длинные имена/URL и RU/EN/ARM тексты.
5. Вести QA matrix и screenshots со ссылкой на **точный commit**. Вся страница должна быть пригодна для настоящей работы, а не только красиво смотреться в Chrome 1440.

**Gate:** все P0 UX-ошибки закрыты и визуально приняты владельцем; платный AI всё ещё OFF.

---

## 7. Целевая архитектура Relay Workspace и AI: от OFFLINE до коммерческого ядра

### 7.1 Продуктовая гипотеза

Turbo Chat — уже реальный Rails messenger. Следующий продукт — **Relay Workspace**, где `разрешённый разговор → явный контекст → полезный результат → ревью/версия → утверждение → экспорт`. AI-native — не отдельный бот на каждый экран и не «Telegram-клон с GPT». Потенциальные первичные клиенты (ещё не подтверждены): фрилансеры, digital-студии, контент-команды, которые обсуждают текст, задачи, предложения и материалы с заказчиками.

**Коммерческий KPI** после запуска пилотов: время до ценного deliverable, доля принятых без существенных исправлений, повторные команды, реальная себестоимость inference, оплаченные подписки/пилоты и удержание. Гипотеза ICP ≠ доказанная платёжеспособность.

### 7.2 Информационная архитектура

```text
GUEST
  ├── Home (truthful current capability)
  ├── Log in / Sign up / Password recovery
  ├── Privacy / Terms / AI notice (при commercial AI)
  └── 404 / 422 / 500 first-party fallback (H2.5)

AUTHORIZED
  ├── Home (continue room, unread alerts, recent scoped rooms, quick actions)
  ├── Conversations
  │   ├── Direct messages
  │   ├── Public rooms / Discover / Join / Leave
  │   ├── Private groups / Invite / Remove / Leave
  │   └── Room details / Presence / Mute
  ├── Composer (own draft, browser spellcheck, Apply/Undo, manual Send)
  ├── Activity & History (authorized search)
  ├── AI Workspace (current: offline preview; later opt-in inference)
  ├── Deliverables (future: brief/proposal/content plan, source/version/approve/export)
  ├── Tasks / Approvals (future)
  ├── Account / Privacy / Notification settings
  ├── Workspaces / Teams / Client roles (future)
  └── Usage / Billing / API / Integrations (future, only after actual backend)

SYSTEM: access revoked / reconnect / errors / retry / offline / empty / privacy export / restore
```

Оставить текущие действующие пути, **не показывать фиктивные пункты будущих функций**. Room-context AI выбирается внутри комнаты; global AI без source/room scope не должен иметь молчаливого доступа к истории.

### 7.3 H3 — Gate 2C: первый реальный AI, ТОЛЬКО после отдельных approvals

**Сейчас: OFF; код H1 ADR — ещё не работающая система.**

1. Проверить по официальным действующим условиям выбранного provider: model/version, data retention/training и storage regions, цены в реальной валюте, лимиты, разрешённость использования для оператора/клиентов, обработка PII и контракт. Никакой provider из личного ChatGPT не становится автоматически backend-поставщиком.
2. Получить явное решение владельца по: provider/model; способ оплаты и подтверждённый legal payout/cost route; maximum per request/day/month spend; состав передаваемых данных; consent user/room; retention/erasure; когда можно создавать AI tables/migrations. Без этого никакого real network inference.
3. **План миграций отдельно от их применения:** будущие `ai_request`, consent policy versions, budget reservation/usage ledger, approved sources/outputs; новые таблицы и названия — гипотезы до ADR approval. Backup и rollback сначала, затем ограниченная migration.
4. Ввести **единый server-side admission gate**: authentication → live membership → source rights → consent version → provider allowlist → budget reserve → immediate dispatch-time recheck → bounded LLM call → validate output → settle usage → user review.
5. MVP только **own-draft manual**: пользователь сам вводит <= установленного server limit, выбирает Polish/Professional/Translate, явно подтверждает отправку провайдеру, получает candidate + diff, Apply/Undo, затем **отдельно Send**. `AUTO OFF` и selected history OFF в первом релизном срезе.
6. Устойчивость: timeout, cancel best effort, retry/idempotency, exponential backoff в пределах бюджета, circuit breaker/kill switch, provider unavailable, price changes, stale draft/source, token caps; no private payloads in logs.
7. Tests: fake model unit + negative ACL/consent/budget tests + e2e one real test **на безличном demo text**, owner принимает реальный отклик и подтверждённую стоимость.

**Выход H3:** реальная по согласию коррекция своего черновика с прозрачной стоимостью и без автоотправки; не делать AI context/history по инерции.

### 7.4 H4 — Gate 2D: Scoped Context и коллективные разрешения

1. Разделить `own draft`, `selected own messages`, `other participant DM messages`, `private group history`, `public joined room history`, `attachments`, `cross-room`, `connected apps` — разные классы прав, согласия и доказательств.
2. Для DM/приватных групп определить применимую, юрпроверенную policy и участника/владельца комнаты, возможность отказаться и отозвать согласие. Видимость сообщений **не равна** разрешению отправить их внешнему LLM. Public внутри Turbo Chat **не означает public for AI providers**.
3. UI `Select sources → preview exactly what leaves app → approve → process → verify result`. Ограничить размер, тип, происхождение, версии и давность выбранных сообщений; проверять live membership и revoke перед outbound.
4. Smart history OFF по умолчанию. После approve: contextual reply/translate, summary/decisions/action items только со ссылками на источники и отметкой недостающих сведений, user review перед записью/экспортом.
5. Negative tests: former member, revoked room consent, malicious prompt injection inside chat, stale cached IDs, cross-room leakage, private blobs, actor change, retry racing with revoke.

**Выход H4:** есть доказанная матрица consent и provenance, запрещённый/отозванный контекст **никогда** не проходит pre-dispatch gate.

### 7.5 H5 — Gate 3: Content Intelligence / Deliverables (коммерческое ядро)

1. На одной подтверждённой задаче клиента строить `Conversation → Brief`: факты vs предположения, цель, аудитория, tone, канал, ограничения, неизвестные поля, ссылки на источники.
2. Первые 1–2 шаблона по реальному спросу: `Professional Client Reply`, `Proposal/Technical Brief`, затем Content Plan/Marketing copy/SEO outline. Никакого огромного магазина неподтверждённых пресетов.
3. `Draft → revision → review → approve → export`: версии, author, reviewer, source message IDs, approval status, контент-права, история изменений, content ownership.
4. Brand Voice / custom presets и RU/EN translation с faithful meaning и human review; отдельный Rails-first контент-движок можно выделить позже для Content Beautifier, **не делать микросервис сейчас**.
5. Контент должен экспортироваться только по действующим правам: Markdown/HTML первыми, PDF/DOCX по отдельной проверке зависимостей и прав. Не отправлять в Gmail/Drive/WordPress без отдельного разрешения на конкретное действие.
6. Измерить 2–3 пилота: сколько времени сэкономлено, сколько правок, уплачивали ли за результат, реальные token spend/модель, нет ли утечки контекста.

**Выход H5:** команда вручную утверждает и получает пригодный к работе документ/предложение **из разрешённого обсуждения**, а не просто красивый AI-ответ.

### 7.6 H6 — Teams, integrations, automation, API: после доказанного спроса

- Team/workspace tenant model, member/client permissions, invites, owner/editor/viewer, приватность между клиентами; строгая ACL матрица.
- Рабочие approvals, explicit task states, no fake project-management UI без persisted backend.
- Интеграции Gmail/Google Drive/CRM: сначала read-only with minimum scope, затем отдельные write scopes и human confirmation; tokens в secret storage, scopes/retention/audit и revoke.
- Automation Studio: вручную запускаемый проверяемый workflow `trigger → approved input → bounded model → validation → human approval → action`; позже schedule/event triggers с идемпотентностью, quota и audit. Никакой бесконтрольной агентной автономии.
- Versioned API, webhooks, rate limits, optional SDK только при коммерческой потребности. Массовый SPA rewrite/WebRTC calls/mobile-native не относятся к первому коммерческому MVP.

**Выход H6:** роли и external side-effects проверены end-to-end, стоимость ограничена, нет cross-tenant leaks.

---

## 8. H7 — непрерывная надёжность и финальный security/UX gate

### 8.1 Security/ACL adversarial matrix

Для каждого действия HTTP/ActionCable/ActiveStorage/search/AI/export проверять **guest / owner / member / unrelated user / former member / revoked consent / disabled provider**; отрицательные тесты обязательны.

- Содержимое DM/private group, media blobs и signed URLs не доступны без текущего membership, включая direct object references и многовкладочные stale websocket subscriptions.
- Server authoritative CSRF, clickjacking, XSS/CSP, injection, SSRF, uploads (MIME+bytes+count), rate limits, secret-handling, no client-side authorization as source of truth.
- AI prompt injection и model output — недоверенный контент; escape/render and sanitization, source provenance, no automatic approval/sending.
- Deletion/export/retention/consent revocation не обещать до фактической реализации; логи без приватных сообщений и токенов.

### 8.2 Realtime и media

- Два настоящих браузера Jack/Eric: send/edit/delete/reply/react, reconnect, missed events HTTP sync, typing/presence TTL, invisible, unread cursor, mute/unmute, multi-tab, cross-process Redis.
- Browser attachments: drag/drop, image thumbnails, file size/count limits, AV range playback, unsupported MIME, attachment-read revoke, graceful failure; browser camera/mic permissions; не потерять текст/файлы при навигации/timeout.
- **Отложенная проблема:** проверить physical mic Linux Mint на уровне PipeWire/ALSA отдельно от Rails voice transport. Не считать «файл записался» достаточным тестом **разборчивой речи**. Пользователь решил отложить до финального QA.

### 8.3 Accessibility / performance / resilience

- 320, 390, 768, 1024, 1440, короткий viewport, 200% zoom, touch, keyboard, screen readers, focus order, aria, contrast WCAG 2.2 AA, light/dark/system, prefers-reduced-motion.
- Large room pagination, message history, empty/loading/error/timeout/offline/mute, notification counts and long texts, concurrent write/read, no mislabeling stale/unread.
- Backup/restore runbook: локально уже был изолированный restore drill; **production** требуется отдельный consistency-aware backup of PostgreSQL **и** ActiveStorage volumes, actual restore rehearsal and failure recovery.
- RUM/alerts/logging, incident/rollback plan, dependency audit, synthetic monitoring, rate limit testing, docs for QA and reproducibility.
- Исследовать 3 старых Rails skips, решить/документировать до release candidate; не подменять их зелёной статистикой.

**Выход H7:** нет известных critical security/reliability/accessibility blockers; owner принимает реальные screenshots/flows; есть документированные ограничения и повторяемое восстановление.

---

## 9. H8 — staging, production, legal, monetization и коммерческий release

**Запуск нельзя делать автоматически по завершению H2.5.** Отдельный gate владельца для каждой необратимой/платной части.

1. **Scope релиза:** определить MVP и pilot audience; нельзя обещать контекстный/платный AI, пока это OFF. Согласовать KPI, SLA разумного уровня и what is explicitly not supported.
2. **Ops budget:** отдельно утвердить Railway/альтернативный hosting, PostgreSQL+Redis, persistent object storage, backups, monitoring, AI calls; смета monthly + worst-case caps. Проверить доступные законные платежи для реального оператора бизнеса, не считать карту эквивалентом payout.
3. **Staging:** новая изолированная конфигурация, секреты только в secret manager, TLS/WSS, email delivery, безопасный seed без Jack/Eric приватных данных; `TURBO_CHAT_STORAGE_ROOT` должен указывать на действительный persistent mount вне `Rails.root` и tmp. Production Redis cache/service verified; backups both DB+blobs.
4. **Legal/privacy:** реальная privacy policy, Terms, data controller/processor, retention/deletion/export/consent, third-party provider DPA, international transfers, invoices, company/tax; юридическая проверка по действующим условиям, не симулировать compliance.
5. **Preproduction release gate:** exact commit CI; Docker/health; real staging sign-up/email reset, invite/membership revoke, attachments and backup/restore drill, failure behavior, AI permission and budget, mobile UX, latency, rollback.
6. **Launch:** пользователь явно утверждает merge PR #2 / release tag / deployment / domain; постепенно включать внешний доступ, не отправлять real client data в необкатанные AI фичи.
7. **Product proof:** разрешённые скриншоты/video, README RU/EN, marketing case с точными ссылками на source SHA, честный status; пилоты по согласию, реальные invoices/subscriptions and retention, support SLA; пересмотреть roadmap по фактической оплате и usage.

**Definition of FINAL:** коммерческий релиз публично доступен по HTTPS, безопасен, data recovery реально проверен, права участников/AI consent/usage работают, продукт доставляет оплачиваемую пользу, измерены реальные пользователи и легально доступные средства. Пока эта цепочка не доказана — `development / staging / beta`, не «готовый SaaS».

---

## 10. Порядок реализации: зависимости, приоритеты, критерии

```text
NOW: HEAD 4d3ff99, PR #2 Draft, H2.4 signed-in Home owner accepted
   │
   ├─► H2.5 FIRST: brand favicon/touch + self-contained 404/422/500
   │       └─► exact-SHA CI + owner screenshot (tab + one error page)
   │              └─► H2.6 core UX / guest / errors / a11y acceptance
   │
   ├─► H1/Gate 2B.6 ADR already exists (offline policy + tests)
   │       └─► separate provider/consent/budget/migration APPROVAL
   │              └─► H3 first manual own-draft real AI
   │                     └─► H4 selected context with participant consent
   │                            └─► H5 source-linked deliverable/approval/export
   │                                   └─► H6 team integrations/automation/API by demand
   │
   └─► continuous H7: security/QA/performance/backups/a11y
               └─► H8 approved staging → live release → measured pilots/business
```

**P0 сразу:** H2.5; no data loss; exact ACL; honest UI; CI; исправления реальных критических дефектов.  
**P1 после core UI:** разрешённая настоящая AI own-draft функция и один deliverable use case; production security & privacy.  
**P2 позднее:** RAG across docs, autonomous agents, multi-provider orchestration, enterprise SSO, mobile apps, WebRTC video calls, complex subscription tiers — **только по demand**.

Не давать календарные обещания без измеренной скорости, бюджетных ограничений и согласованного scope. Этап считается «готов» только при его тестовом и owner gate.

### 10.1 Release-матрица по слоям

| Слой | Unit/Request | Chrome/Two sessions | Owner local | Prod/staging |
|---|---|---|---|---|
| Navbar/Home/Account/Auth | PASS `4d3ff99` | PASS CI | Signed-in Home/Profile accepted | Не проверено |
| Activity selectors | PASS | PASS CI | Accepted screenshot/feedback | Не проверено |
| Writing editor/offline AI | PASS | PASS CI | Desktop accepted, AI OFF | Не применимо |
| Favicon/static errors | **Не выполнено** | Не выполнено | **Не принято** | Не выполнено |
| Real provider/consent/budget | **Не существует** | Не выполнено | Не разрешено | Не разрешено |
| Scoped summaries/deliverables | Не существует | Не выполнено | Не разрешено | Не разрешено |
| Production backup/legal/payments | Локальный runbook | Pilot testing позже | Не разрешено | Не проверено |

### 10.2 Защита от «ложного прогресса»

- Коммит и зелёный CI ≠ визуальная приёмка владельцем.
- `docker compose up` ≠ production deploy.
- Файл `favicon.ico` ≠ узнаваемый правильный favicon в Chrome.
- Наличие `public/500.html` ≠ проверенный 500 fallback и response status.
- Browser `Friendly` preset ≠ реальная модель или consent.
- `AI OFF` и `AUTO OFF` ≠ ошибка, пока у продукта нет официально разрешённого provider.
- Демо-логины Jack/Eric ≠ реальные клиенты, подписки или выручка.
- Существующий банк/карта ≠ verified legal billing/payout.

---

## 11. Safe Git / Docker / backups: инструкции новому чату

### 11.1 Только read-only на старте

```bash
# В существующем каталоге turbo_chat на Linux Mint, НЕ новый clone:
pwd
git status -sb
git rev-parse HEAD
git log -1 --oneline
docker compose ps
```

**Ожидаемый исторический факт:** branch `feat/security-baseline-2026-11-03`, local `4d3ff99`, `M db/schema.rb`, web/DB/Redis в рабочем состоянии. **Новый chat обязан проверить актуальные данные.**

### 11.2 Только после успешного exact-HEAD CI на GitHub

```bash
# git status сначала: если есть неожиданные изменения — НЕ перетирать.
git fetch origin feat/security-baseline-2026-11-03
git merge --ff-only FETCH_HEAD
# после проверки что git merge завершён и новой миграции нет:
docker compose up -d --build
git rev-parse --short HEAD
docker compose ps
```

`git merge --ff-only` безопасен только когда локальное состояние допускает fast-forward; остановиться при ошибке, **не** использовать reset-hard. Если Git сообщает conflict с локальным schema diff — остановиться, отдельно сохранить diff и не терять данные.

### 11.3 Данные и миграции

- `db/schema.rb` намеренно изменён локально. Не писать/пушить его из-за косметики, не откатывать молча. Если появятся нужные DDL — отдельное техническое согласование и backup plan.
- `storage/` находится на bind mount Linux host, Postgres — named Docker volume; `docker compose down -v` удаляет критичные данные.
- Перед любыми production или owner-local миграциями использовать защищённый backup PostgreSQL + ActiveStorage, верификацию checksum и изолированный restore; backup — **private**, не коммитить/не класть в публичный AI-indexed Drive.
- Ни в GitHub, ни в ChatGPT документы не загружать дампы реальных переписок и секреты. Логи/скриншоты можно обезличивать.
- No new external deployment, provider, AI costs or production operations until concrete owner approval.

---

## 12. Тестирование и приёмка: как именно проверять каждую поставку

Для каждого следующего commit на точном SHA:

1. **Code quality and boundaries:** отсутствие migration/route/ACL изменений вне scope; no secret changes; reviewed diff; new tests cover actual behavior; no regression in action URLs.
2. **Rails:** request/model/service tests; expected HTTP 401/403/404/422; read-only GET; authentication; search ACL.
3. **Realtime:** Redis and cross-process ActionCable, 2-browser send/receive, reconnect/inbox sync, notifications, stale membership.
4. **Chrome:** affected desktop+390px mobile page, form events, keyboard, focus, screenshots, light/dark/system. Preserve localStorage/selected settings where applicable; avoid cross-test leakage.
5. **Security:** bundler/Ruby advisories, JavaScript advisory scanning, Brakeman; static HTML no private stack trace; CSP/no CDN.
6. **Docker:** dev build, HTTP, file retention across restart; existing volumes intact. Separate production restore later.
7. **Owner:** one exact path + 1–3 actions + screenshot/response; status `owner accepted` only after confirmation.

**Текущий CI base:** Rails 274/2001/3 skips, Chrome 74/1115, Redis 2/6, Cable 1/5; Security and Docker PASS at `4d3ff99`. Новые тесты увеличат эти числа; не принимать жёстко старые counts как обязательную константу.

**Exception:** на Rails development при искусственном `/nonexistent` можно увидеть debug page, а не `public/404.html`. Поэтому static assets проверять автономно и воспроизводимо в production-like тестовом окружении, без модификации настоящего production.

---

## 13. Product/UX дизайн-правила, которые владелец уже утвердил

**Базовый стиль:** Signal Deck / Quiet Canvas (тёмный, светлый и system): компактная типографика, спокойные фоновые поверхности, purple/blue accent для интерактивных элементов, единые stroke SVG через `sd_icon`; **не превращать страницы в Bootstrap/cards с толстыми рамками**. Внешний бордюр на writing panels владелец прямо попросил убрать; ориентироваться на принятый sidebar и Profile.

**Semantic tokens:** `--sd-canvas`, `--sd-surface`, `--sd-surface-2/3`, `--sd-text`, `--sd-muted`, `--sd-accent`, `--sd-accent-strong`, `--sd-success`, `--sd-warning`, `--sd-danger`, `--sd-focus`. Не вводить десятки random HEX в работающие SCSS; для **изолированного static error HTML** допускаются self-contained аналоги тем, чтобы ошибка отображалась даже при падении Rails.

**A11y:** иконка + доступное название, минимум 44px touch, читабельные 11–12px metadata (не бледные 10px), `:focus-visible`, ARIA status и выбранные состояния, usable Enter/Escape, без ненужного внутреннего scrollbar, `prefers-reduced-motion`. Подпись и значение рядом. Кастомный select только с native fallback и полным keyboard contract.

**IA:** Home — hub, Conversations — реальная работа, Activity — поиск и уведомления, Profile — персональные настройки, AI Workspace — закрытый offline/future zone. Не дублировать inbox и не показывать нетронутые/ложные функции.

**UI release states:** default/hover/focus/active/disabled-with-reason/loading/empty/offline/permission-revoked/error/success. Полезность и privacy важнее декора.

---

## 14. Handoff protocol, checkpoint и критерий закрытия

После каждого значимого slice добавить коммент в **тот же PR #2**, при необходимости `docs/CHECKPOINT_YYYY-MM-DD_<topic>.md` и обновить мастер только при фактических изменениях.

Шаблон checkpoint:

```text
Date/time + timezone:
Repo / branch / PR / exact HEAD:
Gate / scope:
Owner request + screenshot/local CLI source:
Verified current behavior:
Changed files + why:
Rails/Redis/Cable/Chrome/Security/Docker URLs and counts (same SHA):
Data/schema/storage effect:
Security/consent/provider/budget status:
Owner-local screenshot/behavior acceptance (yes / pending / rejected):
What is NOT implemented:
Remaining defects/blockers:
Next one-three owner actions:
Next engineering slice + DoD:
```

Статусы строго различать: `не начато`, `план`, `код в PR`, `CI PASS`, `ждём локальный тест`, `принято владельцем`, `ограничено`, `ждём согласования`, `staging tested`, `production live`, `платёж реально проверен`.

**Важный запрет:** не утверждать, что файл из этого чата уже появился в Google Drive, GitHub или другом чате, если не выполнено подтверждённое сохранение/чтение. Отдельный чат должен получить ссылку на реально созданный файл или приложенный `.md`.

---

## 15. Первый рабочий спринт нового чата — без уточняющих вопросов

1. **Read-only GitHub**: PR #2, текущая ветка, HEAD, последняя CI. Прочитать `app/views/layouts/application.html.erb`, `app/helpers/signal_deck_helper.rb`, `public/{404,422,500}.html`, существующие `public/favicon.ico` и `public/apple-touch-icon*`, style tokens, тесты. Старый H2.4 `4d3ff99` считать подтверждённой базой, если branch не изменился.
2. **Сделать H2.5a**: собственный узнаваемый значок на основе уже существующего Turbo Chat brand mark, настоящие favicon SVG/ICO и touch PNG, explicit HTML link tags, тест загрузки/контента; commit, exact SHA CI.
3. **Сделать H2.5b**: полностью self-contained dark/light Signal Deck 404/422/500 без Rails dependencies, отдельные проверяемые HTTP статусы и отсутствие trace; тесты; точный CI; checkpoint PR. **Только после green** дать владельцу `git fetch/merge --ff-only + docker compose up -d --build`, затем попросить screenshot tab favicon и статической 404 (при необходимости standalone file/production-like test); принять замечания.

Не скакать к AI, тарифам, Railway, моделям, новой библиотеке компонентов, публичным demo и миграциям до закрытия H2.5 по owner acceptance. **Если два среза можно объединить без риска — делай**, но всегда с проверяемым статусом и сохранением файлов пользователя.

---

## 16. ГОТОВЫЙ ПЕРВЫЙ PROMPT ДЛЯ НОВОГО ЧАТА

> Продолжай существующую разработку **Turbo Chat / Relay Workspace** в проекте CAREER. Полностью прочитай приложенный `TURBO_CHAT_RELAY_MASTER_HANDOFF_2026-11-09_H25_TO_RELEASE.md` (v3.0). Это источник актуального контекста и плана **от текущей точки до коммерческого релиза**. Не создавай новый проект/ветку/PR. Repo: `TheGor-365/turbo_chat`; branch: `feat/security-baseline-2026-11-03`; Draft PR #2: <https://github.com/TheGor-365/turbo_chat/pull/2>; последний подтверждённый HEAD: **`4d3ff993fc85837e7c3e429412c723cf41d8f63c`**, точный Rails/Redis/Chrome/Security/Docker CI зелёный, локальная Linux Mint копия обновлена и Docker db/redis healthy, **намеренно `M db/schema.rb`**. H1 offline AI consent/budget ADR, H2.1b writing panels, H2.2b Activity filters, H2.3 Account/Auth и H2.4 Home уже сделаны; владелец **принял desktop Profile и signed-in Home**. Реальный AI провайдер, согласие, budget, миграции и production **не разрешены / не реализованы**. **Первое реальное задание — H2.5: оригинальный фирменный favicon с touch assets, explicit link tags и автономные Signal Deck `public/404.html`, `422.html`, `500.html` с корректными HTTP-статусами.** Сначала read-only проверь GitHub HEAD/CI и существующие файлы, затем реализуй этот ограниченный slice в том же Draft PR #2, тесты + exact SHA CI + checkpoint, после зелёных тестов дай мне 1–3 команды на safe local update и запроси screenshot. Никакого `reset --hard`, сброса `db/schema.rb`, удаления volumes/messages/media, новой миграции, merge в main или Railway deployment. Дальше строго по H2.6 → отдельно согласованному real AI H3 → Scoped Context H4 → Deliverables H5 → Teams/Integrations H6 при спросе → H7 hardening → H8 staging/legal/production/commercial evidence. Отвечай по-русски и доводи этапы до законченного проверенного результата.

---

## 17. Финальный краткий status handoff

**Проверено:** GitHub `4d3ff99` PR #2 Draft; Rails 274/2001 (3 skips), Chrome 74/1115, Redis/Cable/Security/Docker PASS; Linux Mint fast-forward и здоровые Docker контейнеры; владелец принял авторизованную главную Home; `M db/schema.rb` сохранён.  
**Создано ранее:** работающий Rails messenger, приватные комнаты/медиа/уведомления/поиск, offline AiWorkspace с ручным editor и шестью пресетами, H1 readiness ADR, H2.1b–H2.4 UI.  
**Не подтверждено / не существует:** брендированный favicon, Signal Deck static errors, гостевой Home screenshot, настоящая AI-модель, user consent/Budget, production, legal billing, реальный payout, sound intelligibility, финальный полный accessibility audit.  
**Первый следующий gate:** **H2.5 brand/icon and 404/422/500**.  
**Сразу после:** exact SHA CI, owner local screenshot, checkpoint; далее H2.6 и только потом следующие AI/production ворота.  
**Главная ценность до финала:** превращать разрешённую коммуникацию в полезный проверенный документ/решение с прозрачными правами, ручным утверждением, реальными расходами и доказуемой пользой для клиента.

### Примечание о публикации мастера в GitHub

Контрольный SHA `4d3ff993fc85837e7c3e429412c723cf41d8f63c` — **последний подтверждённый инженерный код H2.4 и последнее локальное обновление владельца**. После добавления этого Markdown-файла в `docs/` HEAD рабочей ветки станет другим из-за **документационного коммита**. Новый чат должен сначала проверить новый фактический HEAD и его CI; не принимать смену SHA документации за новую функциональность или за новый локальный deploy.