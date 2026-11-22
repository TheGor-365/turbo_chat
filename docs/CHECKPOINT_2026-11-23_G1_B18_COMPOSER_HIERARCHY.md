# G1/B18 — единая точка AI-настроек и сведения о комнате в header

Дата: 2026-11-23 (Asia/Yerevan).  
Статус: **CODE_COMMITTED / CI_PENDING / OWNER_QA_PENDING**, Draft [PR #11](https://github.com/TheGor-365/turbo_chat/pull/11) поверх B17 `861c5dca76e7aff6171292ab97ce9d99304ecefe`.

## Основание — фактическая локальная B17 QA владельца

На скриншотах комнаты `/rooms/3` в desktop dark/light и mobile 400×793 обнаружены:
- Постоянная дублирующая полоса `Состояние / Настройки AI` над input отнимает существенную высоту области сообщений. Мобильная отдельная полоса Status/AI/Tools — второй вход в те же панели.
- Desktop Status первоначально выглядел как широкое окно относительно viewport, а не от границ комнаты.
- В Settings Message и Room повторяется информация о комнате, членах и устройстве, хотя header над сообщениями уже имеет popover участников.
- Значки и компоновка popover участников не унифицированы.

Владелец задал правило: **одна видимая точка управления шестью AI-панелями возле человеческого input, все панели снизу от input; только настройки внутри панели, идентичность/состав/владелец комнаты — в header dropdown.**

## Внесено в код (без изменения схемы БД)

1. Удалена отдельная мобильная триада Status/AI/Tools. Верхние desktop-полосы только скрыты, но их canonical DOM/status/controller живут в едином Status — **без второго владельца состояния**.
2. В `.composer-controls` добавлена одна кнопка `.sd-g1-workspace-launch` → существующий `mobile-composer-hub#openStatus` и его шесть native вкладок. Мобильный Tools запускается через `.sd-g1-attachments-launch` в той же строке; сохранены AI Answer/Beautify как отдельные осознанные операции.
3. Универсальное позиционирование Status/Plan/Context/Instructions/Message/Room по фактическому `.composer-controls`, ширине `#room_container`; compact Status 3 колонки desktop / 1 колонка mobile с live indicators, существующие permission handlers не дублируются.
4. Одна рабочая Undo-кнопка переставлена из скрытой полосы в composer и всплывает **только после Apply**, без фоновых запросов.
5. `sd-ai-room-context` и `sd-ai-draft-context` удалены вместе с ненужной разметкой avatar/device из Room и Message. Изменён один safe guard в `ai_draft_controller.js` для необязательного ранее metadata target; оригинальная логика сохранения предпочтений оставлена.
6. Header `#private-group-details` содержит название, тип доступа, владельца, количество участников и существующий roster/invite/remove. Значки взяты **только из `SignalDeckHelper::ICONS` allowlist** (`users`, `lock`, `chevron-down`). Серверные membership/authorization actions и URLs сохранены.

## Acceptance и доказательства

- Новые Chrome тесты: `test/system/g1_b18_composer_room_hierarchy_system_test.rb`, включены в Focused Chrome CI. В desktop/mobile проверяются единственный видимый workspace-launch, шесть tabs, размер/якорь Status, отсутствие дублирующихся блоков, закрытие, неотправленный текст и отсутствие `AiUsageReservation`.
- Existing B17/Chrome тесты адаптированы для user-visible launcher, **не путем удаления утверждений о consent, bounded Context, revisions, human draft и no-Send**. Старые Rails assertion о клиентском avatar/locale перенесены на текущий источник истины: header/inbox и server-localized launcher.
- Отдельно выявлено, что Undo было скрыто при удалении старой строки; восстановлена доступность одной canonical Undo после Apply.
- Ошибка раннего commit B18 (SVG имена не в allowlist → 500 на private groups) устранена на code review; ранний CI failure исторически остаётся в GitHub.
- На дату checkpoint итоговые **exact-head Focused Chrome, Baseline Rails, Security и Production image проверки ещё подлежат подтверждению**. Не переносить green с B17 SHA на B18. Standalone locale / Docker Compose workflow не triggered by path filters — не говорить `6/6`.

## Безопасность локального владельца и следующий gate

Рабочая машина пользователя остаётся на отдельной локальной ветке `review/g1-b17-owner-2026-11-23` @ `861c5dc` с намеренно изменённым `db/schema.rb`. Есть приватная независимая копия `../turbo_chat_local_backup/schema_before_B17_20261122T213144Z_86VL7r.rb` (mode 0600) и PostgreSQL dump. **Нельзя `git reset/clean/stash`, миграции `db:prepare`, пересоздание db/redis/volumes, merge/main, Railway, платные вызовы AI или реальные Send.**

После успешного **exact B18 SHA** CI: guarded owner fetch → отдельный review branch без db/ diff → JS/CSS rebuild via existing safe Docker override, only web recreate when necessary → screenshot acceptance 1440 desktop and 400×793/390×844 in dark/light (Status/Plan/Context/Instructions/Message/Room, room popover with owner/invite, drag, closing, draft + Undo).

До этой приёмки PR #11 Draft. Функциональные D3.2/D3.3 после B18; D3.4 contract — отдельный gate.
