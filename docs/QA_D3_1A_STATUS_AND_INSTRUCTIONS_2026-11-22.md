# D3.1a — ручная проверка индикаторов и нижних панелей

**Статус:** CODE_COMMITTED / CI_PENDING / OWNER_QA_PENDING, 22.11.2026. Основа: пользователь подтвердил на /rooms/3, что Plan↔Context работает, но статусы пропали. Этот документ не подтверждает проведение нижеприведённых проверок.

## Безопасное получение ветки (только после успешного CI)

```bash
git status --short
git branch --show-current
git pull --ff-only origin feat/ai-answer-readiness-master-2026-11-20
git rev-parse --short HEAD
docker compose exec -T web yarn build &&
docker compose exec -T web yarn build:css &&
docker compose restart web
docker compose ps
```

Не удалять/не stash ` M db/schema.rb`; никакого `db:migrate`, `db:reset`, merge или Railway. После успешного pull/build — Chrome `Ctrl + Shift + R`. Любое падение сборки → остановиться и прислать точный вывод.

## B1. Индикация (лучше в отдельной QA-комнате)

**Видимые шесть полей:** Орфография, Мой допуск AI, История доступна, Автоответ, Перевод, Детали. Индикаторы расположены в отдельной строке над рабочими входами. Зелёный ✔ = включённая настройка, красный × = выключена, янтарный = проверяется, красный «Недоступно» = заблокирован. Нельзя считать зелёный перевод доказательством установленного браузерного языкового пакета.

1. Введите несохранённый `QA D3.1a — не отправлять`. Скриншот B1. Не нажимать Send.
2. Нажмите **Орфография** в статусной полосе: зелёный должен стать красным без обновления страницы; ещё раз — зелёным. Повторите **Детали**, проверьте реальный более подробный вид сообщений, без изменения текстов/SQL.
3. Нажмите **Мой допуск AI**. Должны открыться настройки комнаты для явного решения, *не* появиться новые grants автоматически. **Автоответ** должен оставаться недоступным. Вернитесь к сообщению; в поле всё тот же `QA D3.1a — не отправлять`.

`PASS`: делегирование существующим контроллерам, нет 500/JS ошибок, нет Send, состояния читаемы без переходов. `P0`: скрытое разрешение/отправка; `P1`: индикатор противоречит фактическому переключателю; `P2`: иконки/отступы.

## B2. Инструкции как самостоятельная Plan-shaped панель

1. В QA-комнате нажмите **Инструкции** напрямую (не через старое меню). Должен открыться нижний лист, с заголовком «Инструкции», единственным *существующим* редактором версий комнаты и плавным раскрытием, без посторонней настройки перевода/стиля.
2. Скриншот B2. Поле имени с локализованной подсказкой `Instruction #N` не должно автоматически склеивать её с текстом. В тестовой комнате, если нет ценных ревизий, введите `QA Scope rules`, Tab; имя должно быть ровно `QA Scope rules`. Сохранять версию только с явно синтетическим, безвредным текстом и только в QA-комнате.
3. Закройте Escape; откройте **Комната**. Ожидается другое представление *того же* контроллера с настройками комнаты, а не ещё один отдельно сохраняемый набор инструкций.

`PASS`: один DOM/серверный источник версий и локальные имена шаблонов, отсутствие дубля состояния. `PARTIAL`: старый Room↔Message режим внутри нижнего листа ещё виден (известный технический долг D3.2/D3.3; не считать его удалённым). `P0`: изменение реальной комнаты без разрешения, потеря чужой истории или Send.

## B3. Сообщение/Комната/Plan и мобильная геометрия

1. Откройте **План AI**, затем **Сообщение** — Plan должен закрыться, откроется нижняя панель сообщения; обычный черновик неизменен. Аналогично **План AI → Комната**. Нет перезагрузки, двух наложенных листов, блокировки скролла после закрытия.
2. Переключите интерфейс в светлую тему и затем в узкое окно 390×844 либо Chrome responsive mode. Проверить, что статусная полоска прокручивается горизонтально, подписи и состояния различимы, панели не уходят за экран, можно добраться до кнопки закрытия.
3. Если в Console красное исключение, приложить **только текст ошибки** без cookie, CSRF, session, токенов и клиентских сообщений. Скриншот B3.

## B4. Подкапотная проверка и семантика без расхода

Полный осмысленный диалог Jack/Eric: `docs/QA_SEMANTIC_DIALOGUE_AI_PIPELINE_2026-11-22.md`. Сначала скопировать только сообщения 01–04 в **отдельную локальную QA-комнату**, подтвердить индикаторы/фильтрацию; затем 05–14 проверить priority, 422, частично согласованный scope и отменённые сроки. AI Plan / provider-free Preview — без реального генератора. При необходимости DevTools Network показывает статус endpoint/флаг авторизации, но не копируйте секреты/полное личное содержание в PR.

## Оценка

Для каждой B1–B4: `PASS / PARTIAL / FAIL / NOT_TESTED`, `P0/P1/P2`, фактический скриншот и сообщение о сохранении черновика. Шесть качеств (0–2): видимость состояния, честная семантика разрешений, скорость переключения, доступность клавиатурой/мобильность, отсутствие дублирования/перезагрузки, безопасность данных и Send. **Принято только при отсутствии P0/P1 и прямом подтверждении владельца**.

**Первый ответ владельца:** после обновления и B1 прислать вывод `git rev-parse --short HEAD`, скриншот **до и после** переключения орфографии и один скриншот «Инструкции». До этого не нужно проверять или оплачивать Grok.


## B5–B7. G0 owner 400px findings and patched acceptance (22.11.2026)

**B5 — mobile 390–400px, dark + light:** use Chrome responsive 390×844 and 400×793. With an ordinary **unsent** human draft, the five AI/photo/file/voice/editor tools are on the first grid row and the textarea plus one human Send icon occupy the next. Textarea width must remain legible (DOM test requires >=180px), no vertical one-letter column or horizontal body scroll, camera/file/voice affordances clickable, visible labels for both Message/Room settings. The message bubbles default to **14px**; mobile editor uses **16px** for reliable mobile focus and legibility. Status chips may horizontally scroll, but not the entire page. Check keyboard raise/safe-area. Existing mobile header and left drawer should not regress.

**B6 — Plan and instructions are a single canonical workflow, not two storage owners:** type `QA — НЕ ОТПРАВЛЯТЬ`, inspect Plan Beautify one-shot settings, use its new **Message settings** link and return **Plan AI** in the modal. The Plan shows the current SAVED room instruction revision and content as read-only; an explicit button opens the *same existing RoomAiInstructionRevision editor* through `Инструкции AI`, now a compact bottom sheet. Switch Plan→Instructions→Plan and Plan→Room→Plan, confirm only one UI visible, input unchanged, no generated candidate, no Send, no cost reservation. In Beautify, the Plan should honestly note that room instructions are not sent. Old Room↔Message topbar remains staged technical debt, not accepted as a redesigned unified panel.

**B7 — appearance and keyboard:** repeat mobile screenshot in light theme. `theme#cycle` currently rotates dark→light→system→dark; monitor icon indicates SYSTEM setting, not the absence of the light theme. Report if controls are too hard to discover; do not add a second preference owner. Check Tab, Escape, focus return, reduced-motion. Capture console exception text only; do not post tokens, cookies or private request bodies.

Mark each `PASS/PARTIAL/FAIL/NOT_TESTED` with P0/P1/P2 and owner screenshot. A successful CI run is **not** owner acceptance. No paid model, Send, schema migration, production deploy.


## B8–B12. G1 messenger UX acceptance (owner 22.11.2026)

**B8 — 390/400px composer (P1 blocker):** on room with **unsent** `QA не отправлять`, mobile action row shows only AI mode icon left, editable textarea center (width >=180px, 16px), native Send right. Above are exactly three icon triggers: Status, AI Settings, Attachments. Tapping Status opens modal with six original live status chips; tapping AI opens modal with six tabs (Status, Plan, Context, Instructions, Message, Room); Attachment opens one menu with photo, file, voice. When dialogs close input remains unchanged. Check virtual keyboard, bottom safe area, no horizontal overflow, portrait 320/390/400 and landscape, both themes. Manual Send still works only when deliberately pressed.

**B9 — workspace navigation (one active UI):** navigate `AI settings → Context → Message → Room → Instructions → Plan` and back, with no second dialog/panel shown. Context source choices and Room instructions stay within their canonical controllers; no duplicate writes, grants or hidden AI reservations. Context now bounded as Plan-sized sheet on desktop too. It is currently **several canonical native dialogs with shared tab chrome, not one DOM dialog root**. Test Escape, browser back, keyboard focus and unsaved draft retention; any failure is NOT_ACCEPTED.

**B10 — avatar and themes:** top-right mobile avatar opens account menu (Chats, Activity, Profile, existing theme toggle, RU/EN/ES/HY, Logout); only **one** `theme#cycle` exists in DOM and moves between header and dropdown by responsive size. Desktop nav unaffected. Validate all 3 theme states, accessibility and locale links without lost room context.

**B11 — Home/Inbox and create:** logged-in Home must display first real accessible rooms and unread counts with direct click into room, no marketing headline/description, no leaked chat bodies. Public & Private creation are in a collapsed disclosure and each creates once and immediately redirects to joined chat via original Rails controllers. Quick actions collapsed; Home, Inbox and Activity share four bottom mobile tabs, while active Conversation does not show the bottom tab bar. Respect room ACL; no fake room counter. Guest home remains unchanged.

**B12 — Activity/History:** small heading, notifications and authorized chat history before search, compact 3-way in-page navigation, original filters/media/period/date/pagination and mark-read actions untouched, no cross-room disclosure. Mobile bottom tabs and viewport non-overflow at 320/390/768. Retain ARIA labels and focus targets.

Record each `PASS/PARTIAL/FAIL/NOT_TESTED` with screenshot and exact HEAD. G1 requires 6/6 CI on newest commit AND owner real 400px input/voice/file/dialog manual QA. No paid provider test, no accidental Send, no main/production.

## B13. G1 P1 follow-up (owner screenshots 22.11.2026)
**Expected after exact-head six CI success and safe local asset rebuild:** (a) 1440px desktop hidden G1 avatar details; no oversized photo image; (b) 400px top-right account dropdown closes on outside click and Escape; only single theme#cycle; (c) each of three icons opens distinctly: Status only six canonical status chips, AI only 6 navigation tiles with icons without link underlines, Attachments only photo/file/voice; all bottom sheets fit content without blank 76dvh; (d) Home Create and Quick actions animate open/close and honor prefers-reduced-motion; (e) four-tab bottom nav shows short History/Profile without wrap, profile route shares nav and begins directly with avatar/editable fields while preserving security, AI defaults and deletion; scroll to bottom with comfortable safe-area space; (f) private group Member list shows actual attached authorized avatars (or initials) next to every user. Report PASS/PARTIAL/FAIL and P0/P1/P2 per group, screenshot after fresh Ctrl+Shift+R, exact local HEAD and console exception text (no cookies/tokens). Do not click real Send or invoke paid AI. CI_GREEN does not imply owner accepted.

## B14. Owner visual QA follow-up 2026-11-22
At 400×793 Chrome mobile verify (1) incoming/outgoing Context cards sit on opposite sides with compact readable typography and individual switches, (2) dates From/To on one row, member picker beneath with avatars, (3) AI Plan/Context tabs are icon-led and no link underlines throughout app, (4) no empty context affordance below data, preserved Saved sets, (5) History type filters are seven tiles in two rows not horizontal carousel; long labels stay within tiles, (6) Inbox/Rooms search can scroll all the way past last content above fixed four-tab bar; Profile begins with visible top padding; private group list has bottom breathing room, (7) message action tray tap targets/icons consistent, member details closes on outside click/Escape, (8) six Status settings appear as aligned label/value rows; only ON is green, OFF/locked/pending unchanged, (9) Latest messages label and pending-count aria text are localized in RU/EN/ES/HY. Preserve unsent draft, no paid AI/Send, no migrations. Capture exact local HEAD, status, screenshot and PASS/PARTIAL/FAIL per acceptance; retain Draft PR until owner accepts.
