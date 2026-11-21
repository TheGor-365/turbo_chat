# ADR 2026-11-21 — AI Context Studio: единая точка работы с источниками

**Статус:** D5.1 CODED / QA PENDING; серверные cross-mode sets и полноисторическая AI-генерация НЕ готовы.
**Ветка:** feat/ai-answer-readiness-master-2026-11-20; draft PR #8.
**Приоритет:** docs/AI_MVP_IMPLEMENTATION_MASTER.md + docs/AI_MVP_LIVE_STATUS.md + Signal Deck 2 / Quiet Depth.
**Основание:** скриншот комнаты Project Circle от 21.11: дублированный source editor из чекбоксов M29–M37 и target dropdown внутри AI Plan мешает сценарию выбора контекста.

## 1. Решение

Один интерактивный редактор источников: кнопка «Контекст AI» в комнате → модальное окно Context Studio, desktop до 1120px, mobile full-screen.

Информационная иерархия: область применения (Общий / Answer / Beautify / Auto Reply / Finalizer) → пресеты → поиск/автор/даты → чат-лента с аватарами и тумблерами → статистика → именованные наборы → Apply. Вкладка режима наследует общий набор до явного override. «Вернуть общий» удаляет только override, не трогает shared. Переключение вкладок не вызывает AI и ничего не отправляет.

В панели AI Plan удалён прежний interactive SourceSelection editor и повторный список исходников. AI Plan остаётся read-only диагностикой фактического составленного запроса, а не второй точкой редактирования источников. Дубликаты writing settings и редактирования goals в Plan ещё остаются — D3. Не удалять защищённые RoomInstruction/Preferences/Consent/Evidence/H4/H5 backend ради внешнего объединения.

## 2. Реализованный первый срез

- RoomAiContextMessagesController#index: только POST для поиска (без утечки слов в URL), приватная комната и согласие всех участников, постраничный полный список до 10k, 25 сообщений на страницу, поиск по тексту/автору/датам, DLP и source version через ConversationCoverageSnapshotV2, повторная проверка, приватные cache headers, per-author counts и avatar URL.
- ai_context_studio Stimulus: чат-вид, один source switch на сообщение, solo, все/последнее входящее/по участнику/ручной preset, live counts, named sets только в этом браузере; сохранённые IDs и правила не являются authorizing tokens.
- ai_answer_entry остаётся единственным владельцем подписанного SourceSelection и серверного dry-run. Применение ограниченного выбора идёт через него. Если выбран старый источник вне подготовленных девяти выдержек, Apply НЕ заявляет успех.
- Текущий движок Answer по-прежнему сканирует максимум 240 последних кандидатов и составляет не более 9 выдержек / 2400 символов. «Вся история» в UI означает весь eligible inventory, НЕ «модель получает все сообщения».
- Beautify остаётся own-draft-only, Auto Reply gated, Finalizer ещё не включён. Их scope — только UI-драфт; не называть его работающей конфигурацией AI.
- Имя набора по умолчанию: локализованное имя комнаты + локальные дата/время. Наборы пока не синхронизируются между устройствами и не восстанавливают активную генерацию после reload. Нельзя повторно активировать непроверенную конфигурацию из localStorage.
- RU/EN/ES/HY, sd_icon, ui-select native-backed, темизация через существующие --sd-* токены, reduced motion, keyboard/focus, без платных запросов и новых миграций.

## 3. Строгие контракты дальнейших срезов

1. Различать AVAILABLE (eligible по consent, ACL и DLP), SELECTED (выбранный логический subset), USED (настоящие выдержки в compiled provider payload). Показывать total, per-user, selected, excluded, truncated и модельный лимит.
2. Истина о правах и источниках — Rails/PostgreSQL. При смене author/membership, consent revoke+regrant, message edit/delete, source version, goal revision, сохранённый набор может стать stale; нужна explicit revalidate. Не делать background-paid repair.
3. Серверная persisted модель после backup: AiContextSelectionSet (room/user/name/scope/mode/selection rules/source version/grant fingerprint/lock version). Правила All, LatestIncoming, Participant, Last N, TimeWindow, Search, Explicit IDs, Exclusions. Не дублировать message bodies. Ограничить quota/ACL, rename/copy/delete, version conflicts, clear old sets.
4. Shared room default → optional tool override → one-shot action override, приоритет ниже immutable ACL/consent/security/budget. Без скрытой мутации других режимов.
5. Reply target обязан быть выбранным входящим сообщением; если excluded — выбрать последнее другое eligible incoming, при отсутствии входящих блокировать до вызова модели.
6. Backend retrieval через full-history inventory и индекс: пользователь может выбрать старое сообщение за пределами нынешних 240; server re-ranks и compiles bounded excerpts с provenance. Не копировать тысячи сообщений в модель или браузер за один запрос.
7. AI-фильтр = отдельный согласованный платный шаг: prompt filter как предложение, before/after preview, uncertain matches, approve/undo, лимит стоимости, consent, audit. Query для локального поиска не вызывает модель и не уходит в URL.
8. Будущие пресеты: Все, Последнее входящее, Последние N, Все от участника, Без моих, Период, Только отмеченные, Слова/фразы, Тема с AI-предложением. Фильтр просмотра никогда не изменяет applied selection без явного действия.
9. Saved sets: server name, metadata counts, previous use, copy/rename/delete/undo, stale notice, mode bindings, effective badge. Вложенные файлы/аудио/видео требуют отдельного разрешения; text-only selection не прикрепляет файлы.
10. Диалог: доступный Escape/Back/Close, возврат фокуса, сохранение черновика, no nested-scroll trap, desktop/mobile 320–1920, dark/light, custom dropdown, original avatars, reduced motion, no implicit paid action/Send.

## 4. Срезы и DoD

D5.1 — Single Context Studio modal, consent-scoped full inventory, базовые пресеты, bounded Answer integration, no duplicated source editor. CODED, exact-head CI и owner QA pending.

D5.2 — После локального backup и проверки modified db/schema.rb: server persisted named sets + lock + per-tool inheritance и migrations. Не начинать до owner backup/restore.

D5.3 — Отбор любой разрешённой части полноисторического контекста и secure compile в ограниченный provider payload с provenance, target auto reconcile.

D5.4 — AI-filter propose/approve/undo с подтверждением модели, retention и бюджета; filters type/topic/attachment.

D5.5 — Все четыре AI-функции используют один effective plan; Beautify контекст optional, Auto Reply только по отдельному gated opt-in, Finalizer по умолчанию «Резюме беседы», без automatic Send.

D3/D5.6 — Канонические места для остальных настроек, никакие дублирующие редакторы: goal revisions — Room settings; writing preferences — canonical resolver/room+account settings. Redirect старых affordances только после тестов direct URLs и no-JS fallback.

DoD каждого среза: server tests, focused Chrome, Rails baseline, Docker smoke, Security, Image build на одном SHA; реальный owner screenshot, два пользователя, мобильный/light и no spend. Нельзя объявлять T1/S8/D5 завершёнными только по наличию кода.
