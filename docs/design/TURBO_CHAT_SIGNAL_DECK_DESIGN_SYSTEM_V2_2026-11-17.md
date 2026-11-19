# TURBO CHAT — SIGNAL DECK 2 / QUIET DEPTH
## Продуктовая дизайн-система, UI/UX-спецификация и план безопасного внедрения

**Версия:** 2.0 — нормативный проект, 17 ноября 2026 года  
**Статус:** утверждаемый визуальный и инженерный стандарт; **не реализован автоматически**  
**Приложение:** Ruby on Rails 8.1 / Hotwire / Turbo / Stimulus / SCSS / PostgreSQL / Redis  
**Репозиторий-основание:** `TheGor-365/turbo_chat`  
**Проверенная ветка / SHA:** `feat/security-baseline-2026-11-03` / `f4ae7bcb48718423473c11690f2f315081e88199`  
**PR:** [Draft PR #2](https://github.com/TheGor-365/turbo_chat/pull/2); исходный `main` не трогать  
**Исходные данные:** 15 скриншотов владельца от 17.11.2026, точечный аудит ERB/SCSS/Stimulus из GitHub, требования владельца из текущего диалога, стандарты W3C/MDN.  
**Название направления:** *Quiet Depth* — спокойный объём, качественная типографика, содержимое важнее интерфейса.  
**Важное ограничение:** снимки показывают тёмную тему на десктопе 1920×1080; светлая тема, мобильные версии и состояния после миграции **не проверены визуально**. Предложенные цвета, масштабы и эффекты — проектные токены, не описание уже установленного CSS.

---

## 0. Короткий контракт для любого следующего чата/разработчика

> **Сохраняй работающий Rails/Hotwire-мессенджер. Применяй Signal Deck 2 / Quiet Depth. Не переписывай страницы с нуля, пока не проверил существующие partial, Stimulus controller, CSS и тесты. Все поверхности используют единые семантические токены dark/light; никаких случайных hex-цветов, больших декоративных рамок, браузерных селектов в итоговом интерфейсе, непереведённых строк, внезапных переходов и лишних постоянных инструкций. Primary UX — переписка, Beautify / AI Answer и навигация по комнате; вторичные действия в компактных панелях. У каждой функции — узнаваемая фирменная иконка, у каждого участника — аватар/fallback. Максимум одна основная кнопка действия на контекст. Плавность не отменяет клавиатуру, доступность, мобильную эргономику и право выключить анимации. Не меняй ACL, consent, AI billing, отправку, сохранение и данные из-за косметического рефакторинга. Внедряй вертикальными срезами, с visual regression на обеих темах и мобильных ширинах.**

**Сфера обязательности:** новые компоненты и изменяемые экраны. Старые компоненты постепенно переводятся на стандарт без одномоментной глобальной ломки.

## 1. Визуальная концепция и принципы

### 1.1. Позиционирование

Turbo Chat — **универсальный AI-first мессенджер**, а не CRM и не редактор договоров. UI служит трём режимам: **Beautify**, **AI Answer**, **Auto Reply**. Иерархия: **сообщения → общение/композер → настройка AI → работа с диалогами → специальные рабочие документы**. Никакой отраслевой терминологии на верхнем уровне. Сохраняются используемые имена продукта **Turbo Chat** и существующая визуальная идентичность Signal Deck.

### 1.2. Восемь правил

1. **Контент выше обвязки.** Не превращать каждый режим в отдельную страницу. Один ясный главный сценарий, вторичное — внутри разворачиваемых секций.
2. **Объём вместо рамок.** Различать уровни относительной светлотой поверхности, расстоянием и контролируемой тенью. Бордюры используются для полей и focus/required semantic states, а не как декор карточек.
3. **Спокойный характер.** Холодный нейтральный ink/slate, один брендовый lavender-акцент, приглушённый sea-glass для AI. Не «школьный» синий и не кислотные градиенты.
4. **Плавное взаимодействие.** Hover/reveal/expand/modal — предсказуемые 110–300 ms. Никакого параллакса, непрерывных пульсаций и внезапной смены высоты/положения поля ввода.
5. **Мобильность без потерь.** Каждое действие доступно на 320–360 px, без обязательного hover, с касательной целью 44×44 px там, где это возможно. Desktop — расширение мобильной схемы.
6. **Единство интерфейса.** Все страницы: одна шкала размеров, шрифтов, компонентов, диалогов, селектов, back/close-правил, языков и состояний.
7. **Одна иконография.** Повторно использовать `SignalDeckHelper#sd_icon`; добавить контролируемые двухцветные варианты, а не устанавливать новые случайные icon packs.
8. **Без UX-обмана.** Disabled всегда объясним; AI-генерация, translation fallback, согласия и расходы показаны правдиво, без имитации готовности.

**Дизайн-инвариант:** интерфейс выглядит деловым и дорогим не потому, что всё переливается, а потому, что пользователю понятно, **что делать, что произойдёт и как вернуться обратно**.

---

## 2. Аудит текущей реализации — не уничтожать то, что уже хорошо

### 2.1. Проверенный кодовый фундамент

| Реализовано | Где | Решение |
|---|---|---|
| Базовые dark/light токены, theme cycling `dark → light → system` | `app/assets/stylesheets/signal_deck.css`, `app/javascript/controllers/theme_controller.js` | **Сохранить механизм**. Заменить семантические значения, расширить роли. Не создавать вторую независимую тему. |
| Система иконок с allowlist, единый SVG stroke | `app/helpers/signal_deck_helper.rb` | Расширить двухцветными слоями; не заменять библиотекой «для красоты». |
| Кастомные селекты поверх семантического `select` | `app/javascript/controllers/ui_select_controller.js`, `chat_signal_select.scss` | **Повторно использовать**; доработать цвета, фокус и popup, не дублировать. |
| Диалоговые окна редактирования сообщения/настроек комнаты | `app/views/layouts/_new_message_form.html.erb`, `ai_draft_controller.js` | Сохранить переключение и сохранение настроек; привести навигацию к 3 зонам. |
| Работающая комната: сообщения, реакции, attachments, перевод-оригинал, композер | `signal_deck_refinement.css`, `chatroom.css`, текущие partial | Шлифовка — никаких крупных переписываний потока сообщений. |
| Аккаунтные и комнатные AI writing preferences | `AiAccountWritingPreference`, `AiRoomWritingPreference`, `WritingPreferenceResolver` | Оставить модель и приоритет настроек; унифицировать карточки и поля. |
| Поиск, уведомления, история, доступ по комнатам | `notifications/index.html.erb`, существующие контроллеры | Доработать иерархию/аватары, не переписывать API и фильтрацию. |
| Реакция на `prefers-reduced-motion` во многих компонентах | несколько SCSS-модулей | Свести к общим motion-токенам, сохранить локальные исключения. |
| Модальные `dialog`, видимые иконки и фокус-состояния | компоненты Signal Deck | Переиспользовать, исправить недочёты фокуса и поведение `Back`. |

### 2.2. Доказанные причины рассинхронизации

**A. Несколько слоёв CSS с разными источниками цвета.** `application.bootstrap.scss` последовательно импортирует Bootstrap, `custom`, `chatroom`, `signal_deck`, `signal_deck_refinement`, `signal_deck_accessibility`, `chat_ui_consistency`, `chat_ai_coverage` и другие. Даже при наличии CSS variables некоторые ранние правила остаются жёсткими, а более поздние используют многочисленные точечные override. Удалять все CSS сразу нельзя.

**B. Глобальный устаревший scrollbar.** В `chatroom.css` есть `::-webkit-scrollbar { width: 10px }`, светлый `#f1f1f1` track, thumb `#888` и hover `#555`. Это нарушает темный визуальный язык и даёт грубые квадратные полосы на некоторых поверхностях. Другие файлы уже используют `scrollbar-width: thin`, но единый визуальный контроль отсутствует.

**C. Систематические буквальные цвета.** В проверенных исходниках: `chatroom.css` — десятки разных hex, `signal_deck.css` — начальный набор двух тем, `signal_deck_refinement.css` — отдельные цвета bubble/surfaces. В старых правилах встречаются яркие borders и `box-shadow` на focus. Нельзя решить точечно заменой одного `#hex`.

**D. Много конкурирующих CSS-правил.** В исходниках `signal_deck_refinement.css` и `signal_deck_accessibility.scss` есть большой объём `!important`; это признак уже проведённых постепенных UI-фиксов. Новая система должна сокращать специфичность, а не добавлять ещё один слой с сотнями `!important`.

**E. AI-панель тяжела визуально.** На скриншотах: 6 больших карточек стилей, широкие пустые зоны, вложенные disclosure и крупные неактивные карточки. Внизу панели пользователь ищет основное действие. UX не отвечает за 3 секунды на вопрос «что сделать дальше».

**F. Страницы документов и AI Workspace не локализованы.** `app/views/room_ai_deliverable_reviews/new.html.erb` содержит литералы `Review a client document`, `Check each statement`, `Save private draft` и др.; `app/views/room_ai_workspaces/show.html.erb` — `AI Workspace`, `Choose exactly what AI could see` и др. В скриншотах RU это отображается по-английски. Исправление через I18n, а не перевод только заголовка.

**G. Документальный workflow похож на внутренний стенд QA.** Длинная страница проверки документа, много ручных шагов, повторяемый Markdown, отдельный блок сравнения, длинные пояснения и лишние переходы. Функции сохранения, версий и проверок **оставить**, оболочку — заменить на компактный task flow в модальном рабочем пространстве.

**H. Контентные списки без стабильной идентичности людей.** На странице событий и истории, в отдельных сводках/выборках вместо визуальной связи с участником доминируют текст и общие значки. Ввести единый avatar component, но не смешивать иконку события с аватаром автора.

### 2.3. Разбор 15 скриншотов владельца от 17 ноября

| Экран / скриншот | Сохранить | Исправить | Приоритет |
|---|---|---|---|
| Комната `/rooms/3`, чат и сообщения (`171526`, `171638`) | Внятная тёмная база, две стороны переписки, спокойный compose, простая левая навигация | Больше глубины в зоне сообщений; единый радиус, «парящие» bubble, внимание к контрасту и структуре заголовка | P1 |
| AI Editor / стили (`171543`) | Группировка карточек, понятные пресеты | 6 плиток не должны постоянно занимать весь экран; 2–3 видимых + «Все стили», компактная сетка, основные действия сверху | P0 |
| AI tools / context / бизнес-блок (`171554`) | Контекстные инструменты и source review | Убрать визуально огромные пустые disabled-карты, показать 1 главный CTA и причину недоступности под ним | P0 |
| Privacy/Cost и завершение (`171602`) | Проверки ACL/расходов нужны | Переместить подробности под «Приватность и стоимость»; над fold не показывать длинные тексты | P1 |
| Настройки комнаты, профиль/язык (`171613`, `171623`) | Конфигурации и серверное сохранение, две темы уже задуманы | Единая геометрия карточек, более компактные подсекции, понятные on/off состояния, двухцветные icons | P0 |
| «События и история» (`171654`, `171719`) | Хорошие фильтры поиска и категории | Аватары авторов/собеседников, меньше пояснений, выразительнее результат, крупные интервалы пустоты уменьшить | P1 |
| «Профиль и настройки» (`171758`, `171808`) | Логичная структура профиля и preferences | Убрать светящуюся яркую обводку у инпутов, согласовать карточки и высоты, hide необязательные тексты | P1 |
| «Проверить документ» (`171842`, `171854`, `171904`) | Автоматический локальный draft, выбор типа, проверки, сохранение версии, сравнение | Полностью изменить **UX оболочку** на переведённую модалку-шаги, не удалять логику/данные | **P0** |
| AI Workspace (`171917`) | Список задач, разрешения, документы, системные gates | Убрать standalone-ощущение, перевести, открыть как task sheet; «создать результат» прежде параметров безопасности | **P0** |

**Граница вывода:** это аудит показанных desktop-состояний, а не заявка на полную проверку всех маршрутов приложения. Мобильные и light-состояния требуют отдельного smoke/visual QA.

---

## 3. Дизайн-токены V2 — точная цветовая система

### 3.1. Эстетика палитры

- **Dark:** neutral deep ink с незначительным сине-серым подтоном, много градаций поверхностей, лавандовый `Iris` только для действий и фокуса, `Sea Glass` для AI и информативных маркеров.
- **Light:** мягкий холодный porcelain, белые карточки, тёмный ink-текст, приглушённый фиолетовый для CTA, мягко окрашенные входящие/исходящие пузыри.
- **Доля акцента:** ориентир до 5% видимой площади экрана; нельзя заливать им каждую активную карточку.
- **Не подменять роль случайным цветом:** успех ≠ бренд, ошибка ≠ красная заливка всего контейнера.

### 3.2. Таблица точных HEX: **нормативные значения V2**

| Семантическая роль | Dark | Light | Назначение |
|---|---|---|---|
| `canvas` | `#0C1019` | `#F5F6FA` | Основной фон, «пространство» вокруг карточек |
| `shell` | `#111723` | `#EFF2F7` | Topbar, rail, глубинный слой |
| `surface` | `#161D2A` | `#FFFFFF` | Панели, диалоги, карточки |
| `surface-raised` | `#1C2634` | `#F0F3F8` | Вложенные и приподнятые карточки |
| `surface-hover` | `#263344` | `#E6EBF3` | Hover/selected-secondary |
| `field` | `#131C2A` | `#F7F9FC` | Поля ввода / editor |
| `bubble-incoming` | `#202C39` | `#EDF1F7` | Входящие сообщения |
| `bubble-outgoing` | `#21404A` | `#E2F0F1` | Исходящие сообщения |
| `text-primary` | `#F2F5FA` | `#192331` | Основной текст |
| `text-secondary` | `#C9D2E1` | `#3C4B5D` | Вторичный текст |
| `text-muted` | `#AAB6C8` | `#536578` | Метаданные, подписи |
| `accent` | `#A69BFF` | `#5144B7` | Links, selected icons, акцентный текст |
| `accent-fill` | `#5B52BE` | `#574DC4` | Primary button с белым текстом |
| `accent-on-fill` | `#FFFFFF` | `#FFFFFF` | Текст на primary |
| `ai` | `#80CBBF` | `#116A67` | AI-specific акцент, вторые штрихи и статус |
| `success` | `#6DD8AD` | `#08775D` | Success, безопасно подтверждённое состояние |
| `warning` | `#F1BF74` | `#976017` | Осторожность и ограниченная готовность |
| `danger` | `#FF929C` | `#AD344C` | Ошибка, разрушительные действия |
| `focus` | `#B8ABFF` | `#564CC5` | Контрастный клавиатурный focus ring |
| `stroke-subtle` | `#3F4B5E` | `#C5CFDD` | Декоративные разделители, не граница интерактивного поля |
| `control-boundary` | `#60738A` | `#7D8CA3` | 1px контур обычных полей, без glow, контраст ≥3:1 с field |
| `scroll-thumb` | `#566477` | `#B4C0D0` | Узкий scrollbar |
| `scrim` | `rgb(3 6 15 / .72)` | `rgb(31 41 61 / .38)` | Подложка модального слоя |

#### Проверка основных контрастных пар (расчёт WCAG, без полупрозрачных наложений)

| Пара | Dark | Light | Минимум |
|---|---:|---:|---:|
| Primary text / canvas | **17.41:1** | **14.66:1** | 4.5:1 |
| Primary text / raised card | **13.96:1** | **14.24:1** | 4.5:1 |
| Muted text / raised card | **7.44:1** | **5.39:1** | 4.5:1 |
| Primary text / incoming bubble | **12.98:1** | **13.97:1** | 4.5:1 |
| Primary text / outgoing bubble | **10.13:1** | **13.55:1** | 4.5:1 |
| Accent text / surface | **7.04:1** | **7.34:1** | 4.5:1 |
| White / primary CTA | **6.19:1** | **6.43:1** | 4.5:1 |
| Focus ring / field | **8.40:1** | **6.15:1** | 3:1 |
| Control boundary / field | **3.52:1** | **3.24:1** | 3:1 |
| Subtle field stroke / field | **1.94:1** | **1.49:1** | Не считать единственным идентификатором поля |

**Обязательный нюанс:** слабая декоративная рамка `stroke-subtle` недостаточна для WCAG 1.4.11, поэтому идентифицируемые стандартные поля используют отдельную 1px `control-boundary` с контрастом не менее 3:1 без свечения. Дополнительно форма поля обозначается label, заливкой и видимым focus-ring. Перед релизом проверить реальные composite colors при opacity, текст на hover, disabled/non-text UI и PNG screenshots через axe/ручной аудит. Указанные пары рассчитаны как непрозрачные HEX.

### 3.3. Канонический токеновый SCSS — пример реализации

Создать **один** файл токенов `app/assets/stylesheets/signal_deck_tokens_v2.scss`, затем контролируемо перенести в него переменные из `signal_deck.css` и `signal_deck_refinement.css`. На переходном этапе использовать адаптер старых имен; не переносить JS-тему в новый механизм.

```scss
/* Signal Deck 2 — reference implementation with one light-theme mixin. */
@mixin sd-light-tokens {
  --sd-canvas: #F5F6FA;
  --sd-shell: #EFF2F7;
  --sd-surface: #FFFFFF;
  --sd-surface-2: #F0F3F8; /* existing alias */
  --sd-surface-3: #E6EBF3; /* existing alias */
  --sd-surface-raised: #F0F3F8;
  --sd-surface-hover: #E6EBF3;
  --sd-field: #F7F9FC;
  --sd-bubble-incoming: #EDF1F7;
  --sd-bubble-outgoing: #E2F0F1;
  --sd-bubble-outgoing-text: #192331;
  --sd-text: #192331;
  --sd-text-secondary: #3C4B5D;
  --sd-muted: #536578;
  --sd-accent: #5144B7;
  --sd-accent-strong: #574DC4;
  --sd-on-accent: #FFFFFF;
  --sd-ai: #116A67;
  --sd-success: #08775D;
  --sd-warning: #976017;
  --sd-danger: #AD344C;
  --sd-focus: #564CC5;
  --sd-border: #C5CFDD;
  --sd-stroke-subtle: #C5CFDD;
  --sd-control-boundary: #7D8CA3;
  --sd-scroll-thumb: #B4C0D0;
  --sd-scrim: rgb(31 41 61 / .38);
  --sd-shadow-card: 0 7px 22px rgb(37 48 69 / .08);
  --sd-shadow-hover: 0 14px 34px rgb(37 48 69 / .14);
  --sd-shadow-floating: 0 25px 70px rgb(37 48 69 / .20);
  --sd-shadow-bubble: 0 4px 14px rgb(37 48 69 / .10);
}

:root, :root[data-theme="dark"] {
  color-scheme: dark;
  --sd-canvas: #0C1019;
  --sd-shell: #111723;
  --sd-surface: #161D2A;
  --sd-surface-2: #1C2634; /* existing alias */
  --sd-surface-3: #263344; /* existing alias */
  --sd-surface-raised: #1C2634;
  --sd-surface-hover: #263344;
  --sd-field: #131C2A;
  --sd-bubble-incoming: #202C39;
  --sd-bubble-outgoing: #21404A;
  --sd-bubble-outgoing-text: #F2F5FA;
  --sd-text: #F2F5FA;
  --sd-text-secondary: #C9D2E1;
  --sd-muted: #AAB6C8;
  --sd-accent: #A69BFF;
  --sd-accent-strong: #5B52BE;
  --sd-on-accent: #FFFFFF;
  --sd-ai: #80CBBF;
  --sd-success: #6DD8AD;
  --sd-warning: #F1BF74;
  --sd-danger: #FF929C;
  --sd-focus: #B8ABFF;
  --sd-border: #3F4B5E;
  --sd-stroke-subtle: #3F4B5E;
  --sd-control-boundary: #60738A;
  --sd-scroll-thumb: #566477;
  --sd-scrim: rgb(3 6 15 / .72);
  --sd-shadow-card: 0 8px 26px rgb(0 0 0 / .18);
  --sd-shadow-hover: 0 15px 36px rgb(0 0 0 / .25);
  --sd-shadow-floating: 0 24px 66px rgb(0 0 0 / .36);
  --sd-shadow-bubble: 0 6px 18px rgb(0 0 0 / .18);
}

:root[data-theme="light"] {
  color-scheme: light;
  @include sd-light-tokens;
}
@media (prefers-color-scheme: light) {
  :root[data-theme="system"] {
    color-scheme: light;
    @include sd-light-tokens;
  }
}
```

**Внимание:** SCSS-фрагмент самодостаточен по объявлению токенов и mixin, но не является автоматическим drop-in патчем: существующие CSS-импорты, переменные, legacy overrides и `data-theme` потребуют контролируемого объединения. Цвета не дублировать в старых файлах после миграции; при необходимости вынести dark-токены тоже в Sass mixin. Темизация должна корректно работать при `data-theme="dark"`, `light`, `system` и переключении системной темы без перезагрузки.

### 3.4. Типографика

- **Шрифт:** сохранить существующий `Inter, ui-sans-serif, system-ui, -apple-system, BlinkMacSystemFont, "Segoe UI", sans-serif`; проверить реальную загрузку/лицензию установленного Inter; запрещено публиковать сторонние бинарники шрифтов без лицензии.
- **Базовый текст:** 14 px / 1.52 desktop, 15–16 px / 1.5 mobile; сами **сообщения** — 15 px desktop и 16 px mobile для длительного чтения.
- **Настройки и формы:** минимум 14 px; `input` и `textarea` mobile минимум 16 px, чтобы избежать автозума Safari iOS.
- **Мета:** 12–13 px с достаточным контрастом (`--sd-muted`), не использовать 10 px для значимой информации.
- **Титулы:** 28/34 px page desktop, 24/30 page mobile; sheet title 20/26; card heading 15/21; section label 13/19 semibold.
- **Вес:** 400 (body), 500 (labels), 600 (actions/headers), 700 только заголовки первого уровня; без капса на каждом элементе.
- **Letter spacing:** `-0.025em` только крупные заголовки; body — `normal`; технические ID — tabular nums, code/monospace.
- **Длина строки:** описания 48–70 символов; длинные исходные тексты читаются в области максимум 72ch. `overflow-wrap: anywhere` только для URL/IDs/длинного unbroken content.
- **Текст ссылок:** без постоянного подчёркивания в навигации/карточках, но текстовые ссылки в обычном абзаце отличать цветом **и** интерактивным признаком; `:hover/:focus-visible` — подчёркивание или явная подсветка. `a` без `href` запрещён.

**Шкала размеров:** `12 / 13 / 14 / 15 / 16 / 18 / 20 / 24 / 28 / 32`. Не заводить 11.5, 13.7, 17.3 для каждого нового блока.

### 3.5. Отступы и геометрия

**Spacing 4-pt base:** `4, 8, 12, 16, 20, 24, 32, 40, 48, 64` px.  
**Контейнеры:** card padding desktop `20–24`, mobile `16`; внутренний gap `8/12/16`; между уровнями секций `16/24`.  
**Радиусы:** icon tile `12`, input/button `11`, card `16`, message bubble `15`, modal `22`, chip/pill `999` px.  
**Размеры управления:** стандарт 44 px высотой на touch, desktop компактный — 40–44; если необходимо плотнее, сохранить 44 px невидимую интерактивную область.  
**Максимальные ширины:** документ `960px`, AI/task sheet `1120px`, account/history page `1040px`, текстовые блоки `72ch`; full-screen mobile.

### 3.6. Тени и глубина

| Уровень | Применение | Правило |
|---|---|---|
| 0 | Canvas, фон, dense rows | Никаких теней |
| 1 | Settings card, sidebar group | `--sd-shadow-card` **только где помогает отделить** |
| 2 | Hover card | `--sd-shadow-hover` + `translateY(-2px)` |
| 3 | Dialog, popover | `--sd-shadow-floating`, scrim и отдельная raised-поверхность |
| Bubble | Сообщения | `--sd-shadow-bubble`, без белого контура |

**«Парящие карточки»**: под сообщениями тёмный canvas, сами входящие и исходящие имеют два разных оттенка и мягкую тень. Для hover у действий/крупных плиток подъём 2 px; не заставлять все сообщения смещаться под указателем мыши. Без тяжёлых blur на каждом скроллируемом сообщении.

---

## 4. Motion system: плавность без замедления

**Нормативные токены:**

```scss
:root {
  --sd-duration-instant: 70ms;
  --sd-duration-fast: 120ms;
  --sd-duration-base: 180ms;
  --sd-duration-panel: 260ms;
  --sd-duration-sheet: 300ms;
  --sd-ease-standard: cubic-bezier(.22, .8, .22, 1);
  --sd-ease-exit: cubic-bezier(.4, 0, 1, 1);
  --sd-card-lift: -2px;
  --sd-radius-input: 11px;
  --sd-radius-card: 16px;
  --sd-radius-modal: 22px;
  --sd-focus-width: 2px;
}

.sd-card--interactive {
  transition: transform var(--sd-duration-base) var(--sd-ease-standard),
              background-color var(--sd-duration-fast) ease,
              box-shadow var(--sd-duration-base) var(--sd-ease-standard);
}
@media (hover: hover) and (pointer: fine) {
  .sd-card--interactive:hover {
    transform: translateY(var(--sd-card-lift));
    background: var(--sd-surface-hover);
    box-shadow: var(--sd-shadow-hover);
  }
}
.sd-card--interactive:active { transform: translateY(0); }

@media (prefers-reduced-motion: reduce) {
  .sd-card--interactive, .sd-sheet, .sd-accordion__content,
  .sd-ui-select__menu, .sd-ai-action {
    transition: none !important;
    animation: none !important;
    transform: none !important;
  }
}
```

- Hover `120–180 ms`, accordion `180–260 ms`, modal enter `260–300 ms`, exit `160–200 ms`.
- Вскрытие секции — мягкий opacity+size; доступность `hidden/inert` синхронно состоянию, не полагаться на `opacity:0` для невидимых focusable элементов.
- Не анимировать `height` списка сообщений при поступлении новых сообщений, не ломать сохранённый scroll position и анкор на последнем сообщении.
- Различать пользовательскую анимацию `hover`, подтверждение действия, network loading и AI generation. Ни одно не должно быть постоянным декоративным циклом.
- Остановить transform/transition при системной настройке reduced motion. GIF/анимация медиа в чате — с пользовательским контролем.

---

## 5. Единая библиотека компонентов

### 5.1. `SDCard`

- 3 роли: `content`, `interactive`, `choice`. Остальное — модификаторы, а не три разных HTML-компонента.
- `background: --sd-surface`, nested `--sd-surface-raised`, `border: 0`, `border-radius: 16px`, `padding: 16/20/24`.
- Header: icon tile 40–42 px, title, **одна** поясняющая строка максимум 60–70 знаков, trailing `chevron/percent/action`.
- Выбранное: тихая заливка и 2–3 px brand indicator внутри карточки, без яркого 1px контура по всему периметру; доступность `aria-pressed/checked` и текст/иконка состояния.
- Hover lift только interactive choice, не на статических карточках.

### 5.2. `SDIcon` / `SDIconTile` — фирменные двухцветные иконки

**Один геометрический язык:** 24×24 viewBox, stroke `1.75–1.9`, round caps/joins, без случайной заливки и без mix Bootstrap Icons/Lucide из разных пакетов на одном экране. Уже существующий `sd_icon` — источник. Нужна **двухцветная композиция**:

1. Основные линии `currentColor`/`--sd-icon-primary`.
2. Акцентная смысловая деталь `--sd-ai` либо `--sd-accent`, **только если SVG действительно содержит второй path с классом**. Нельзя считать одноцветный SVG «двухцветным» только потому, что у его рамки другой фон.
3. Для иконок, не требующих отдельного path, двухтонный вид дают **подложка tile + основной glyph**; настоящую двухцветную форму добавлять постепенно к ключевым 10–15 glyphs.
4. Публичный API: `sd_icon(name, size: 20, variant: :default)` / `sd_icon_tile(name, tone: :ai, size: 40)`, только allowlisted имена и SVG; новые значения `tone` валидируются в helper.
5. `aria-hidden="true"` только если кнопка получает корректный переводимый `aria-label` или рядом есть видимая подпись.

**Функции и соответствующие визуальные метафоры:**

| Функция | Стандартная иконка | Цветовая роль |
|---|---|---|
| Chat/сообщения | `messages` | text/selected accent |
| Beautify | `sparkles` | lavender + sea-glass secondary path |
| AI Answer | `reply` + `sparkles` (одна интегрированная иконка) | lavender / AI |
| Auto Reply | `zap` + `messages` (новый комбинированный glyph) | AI / lavender |
| Перевод | `globe` | lavender + AI latitude detail |
| Настройки сообщения | `pencil` + `sliders-horizontal` | neutral/lavender |
| Настройки комнаты | `sliders-horizontal` | neutral/lavender |
| Работа с диалогами | `messages` + `filter` | neutral/AI |
| Источники / память | `search` | lavender / text |
| Файлы / база знаний | `file-text` + small AI detail | text / AI |
| Цель | новый `target` | accent |
| Готовность / качество | новый `gauge` | success/warning/danger |
| Приватность | `lock` / `shield-check` | muted/success |
| Цена | `wallet` | neutral |
| История | `clock` | neutral |
| Профиль | `user` | neutral |
| Назад / закрыть | `arrow-left`, `x` | neutral |

**Ограничение плотности:** в телефоне в main topbar максимум 3 действия, остальные в `⋯`; в композере одна первичная AI-кнопка, `attach` и `send`, остальные функции в меню. Для иконок без текста: `title`/tooltip при hover + доступное русское/английское `aria-label`, touch-эквивалент через меню; не кодировать значение только цветом.

### 5.3. `SDAvatar`

- **Всегда показывать участника** в DM, шапке комнаты, списках сообщений, настройках участников, событиях, AI citations, review lists и упоминаниях.
- Если есть фото: `object-fit: cover`, скругление `12px` (square-ish для общей системы) либо круг **последовательно во всех местах**, без смешения форм. Для Turbo Chat стандарт: rounded-square 12px.
- Если фото отсутствует: тот же размер, двухцветная подложка `linear-gradient(135deg, var(--sd-surface-hover), color-mix(in srgb, var(--sd-accent) 18%, var(--sd-surface)))`, силуэт или инициалы, второй штрих AI/iris, `aria-label` с именем участника.
- Рекомендуемые размеры: compact metadata `24`, message `32`, room list `36`, member picker `40`, profile `56–72` px. Никогда не заменять аватар автора generic `bell`/`messages`.
- Аватар относится к user, иконка события — к действию; можно показать их рядом, но не подменять друг другом.
- Избегать внешних avatar URL без авторизации и явного разрешения на обработку персональных изображений.

### 5.4. `SDButton`

- `primary`: заполненная iris-кнопка, один главный CTA на modal step.
- `secondary`: tonal surface с текстом/иконкой без рамки.
- `ghost`: только иконка/label, hover surface.
- `danger`: текст/иконка опасного действия, подтверждение при реальном удалении.
- `disabled`: причина в строке под действием или понятном tooltip/Details, а не огромное пустое серое поле.
- `loading`: spinner только пока идёт запрос; disabled удерживает ширину кнопки, не меняет слова так, что страница сдвигается.

### 5.5. `SDField` / `SDTextarea`

```scss
.sd-app :is(.sd-field, .sd-textarea, .form-control) {
  background: var(--sd-field);
  color: var(--sd-text);
  border: 1px solid var(--sd-control-boundary); /* quiet 1px, ≥3:1 */
  border-radius: var(--sd-radius-input);
  box-shadow: none;
  min-height: 44px;
  transition: background-color 120ms ease, border-color 120ms ease;
}
.sd-app :is(.sd-field, .sd-textarea, .form-control):focus {
  /* Avoid bright persistent neon frame on mouse click. */
  background: var(--sd-field);
  border-color: var(--sd-control-boundary);
  box-shadow: none;
}
.sd-app :is(.sd-field, .sd-textarea, .form-control):focus-visible {
  outline: 2px solid var(--sd-focus);
  outline-offset: 2px;
}
```

- Введённый текст имеет первичный контраст, placeholder только вспомогательный; у каждого поля есть `label` (визуальный или `.sd-visually-hidden`).
- `textarea` сохраняет вертикальный resize, если уже нужен для композера; не лишать пользователя управления высотой; autosize не должен затирать ввод.
- **Не вносить этот snippet как слепой глобальный override:** сначала проверить на `.composer-controls .msg-content`, Bootstrap `.form-control`, существующих `:focus`, `:focus-visible`, CSS `!important`, JS-resize. Снять несуществующие/неподходящие селекторы и замерить contrast после компиляции.

### 5.6. `SDSelect`

Использовать **существующий** `ui_select_controller.js` / `chat_signal_select.scss` и Rails `shared/signal_picker` где он уже задействован. Итоговый попап — фирменная floating-поверхность с 44px row, мягким shadow, `aria-expanded`, keyboard arrows/Enter/Escape/typeahead. Настоящий `<select>` остаётся в DOM для семантики и fallback при недоступном JS, но не рисует браузерную меню-панель в enhanced UX.

**Не делать:** `appearance:none` у реального select без пользовательского popup; новый JS picker рядом с существующим; `div` с `onClick` без клавиатуры. Учитывать browser top-layer внутри `<dialog>` и stacking context.

### 5.7. `SDSwitch`, `SDChip`, `SDTooltip`, `SDAccordion`

- Switch: один вариант размера 36×20, thumb 16; ON — sea-glass / accent с текстом «Вкл», OFF — quiet neutral, `role=switch`, `aria-checked`, целевая область 44×44.
- Choice chip: высота 32–36, короткий label, selected tonal fill без насыщенной рамки; отделять выбор категории от destructive toggle.
- Tooltip: только дополнение, не единственный способ получить критичную информацию на телефоне.
- Accordion: заголовок + chevron, 180–260ms; `aria-expanded`, keyboard Enter/Space; закрытый контент не табулируется.
- Длинные объяснения: `Подробнее` раскрывает компактный блок; пользователь должен видеть действие **до** технического описания.

### 5.8. `SDModal` / `SDTaskSheet`

- Desktop `width: min(1120px, calc(100vw - 32px))`, document `960px`; `max-height: calc(100dvh - 32px)`; шапка/подвал sticky, **одна основная** вертикальная область scroll.
- Tablet: `width: calc(100vw - 24px)`, `max-height: calc(100dvh - 24px)`.
- Mobile (`<=599px`): edge-to-edge full-screen sheet `width:100vw; height:100dvh; border-radius:0`, safe area inset, fixed header `Back` и close, sticky main CTA above keyboard.
- `Esc` закрывает, **кроме** случаев, когда несохранённые изменения требуют подтверждения. Кнопка назад всегда видима. После закрытия фокус вернётся на триггер.
- Deep link / прямой URL сохраняется. **Не удалять рабочую Rails-страницу**, пока прямой переход не проверен; task sheet загружать по существующему маршруту через Turbo Frame/response variant. Если JS отсутствует — полноценная доступная страница с кнопкой назад.
- Закрытие модалки не должно терять черновик без предупреждения; переносить только нужное состояние, не дублировать в URL личные данные.
- Не вкладывать `dialog` в `dialog` без строгой необходимости. Для вспомогательного пояснения использовать popover/accordion; для выбора значения использовать имеющийся `ui-select`.

**Навигационная модель:** `Room → TaskSheet → close/back → тот же Room, scroll position, draft, attachments, locale`. Без сюрпризов, без принудительного возврата в inbox.

### 5.9. Scrollbar

```scss
/* Replace legacy global ::-webkit-scrollbar 10px; scope to app. */
.sd-app, .sd-app :is(.sd-scroll-region, .sd-task-sheet__body, #messages-container) {
  scrollbar-width: thin;
  scrollbar-color: var(--sd-scroll-thumb) transparent;
}
/* WebKit fallback where standardized properties are not applied. */
.sd-app ::-webkit-scrollbar { width: 6px; height: 6px; }
.sd-app ::-webkit-scrollbar-track { background: transparent; }
.sd-app ::-webkit-scrollbar-thumb {
  background: var(--sd-scroll-thumb);
  border-radius: 999px;
}
.sd-app ::-webkit-scrollbar-thumb:hover { background: var(--sd-muted); }
```

**Оговорка:** браузер/ОС могут проигнорировать толщину скроллбара или применить overlay scrollbars. Не отключать scrollbar через `display:none` там, где это мешает обнаружить прокрутку. Некоторые движки при `scrollbar-width: thin` приоритетно используют стандартное управление и не применяют `::-webkit-scrollbar` — тестировать Firefox/Chrome/Safari отдельно. Скроллбар не должен перекрывать контент. Не делать нестандартный drag-only JS scrollbar.

---

## 6. Информационная архитектура и навигация

### 6.1. Три уровня AI-интерфейса

**A. «Настройки сообщения».** Параметры **одного** сообщения: исходный черновик / AI Answer без черновика, тон, стиль, язык, длина, выразительность, emoji, инструкция на этот запрос, preview/redo/edit/send. Переименовать пользовательские подписи «Редактировать черновик» в «Настройки сообщения» там, где контролируются параметры ответа; внутренние сущности `draft` **не переименовывать массово**, пока не доказана необходимость.

**B. «Настройки комнаты».** Язык каждого участника (личный), пресет общения, **цель беседы**, разрешения на контекст, кастомные правила комнаты, выбранные знания/файлы, automation mode/limits, readiness. Поля и видимость имеют ACL, ownership и наследование account/room; косметика не меняет consent semantics.

**C. «Работа с диалогами».** Выбор подмножества сообщений, пользователей, даты, поиск, saved selection, summary, tasks, timeline, export/doc creation. Существующие источники/coverage/evidence/document review перевести сюда **без удаления**. Функции «подтверждение M33» не должны быть обязательным шагом написания ответа.

### 6.2. Композер

- Нет текста: одна contextual AI action **AI Answer**, только при выполненной цели/разрешениях; иначе disabled **с причиной**, не создавая впечатления что API не работает.
- Появляется символ: action плавно меняет label/icon на **Beautify**, без прыжка ширины поля, без потери набранного текста.
- Отдельная обычная Send всегда остаётся доступной для отправки человеческого текста.
- Генерация показывает самостоятельный редактируемый вариант, re-generate, стоимость, язык и явно управляемый Send. Сохраняется существующий provenance-механизм AI Send; нельзя автоматически переносить его на генерации иного типа без отдельной серверной проверки.
- При включении Auto Reply во время обычной переписки — компактный, понятный индикатор состояния и доступный pause/kill-switch. Не смешивать готовность автоматизации со статусом online/realtime.

### 6.3. Иерархия действий по устройствам

**Mobile:** `назад | имя/аватар комнаты | AI readiness/progress | ⋯`; composer `AI action | attach | text | send`. Внутри `⋯`: mute, tools, member list, room settings.  
**Desktop:** sidebar + chat + optional transient sheet; в шапке не более 4 коротких действий.  
**Не допускать:** одновременную стойку из 7–9 иконок и три разных перехода к AI Workspace.

### 6.4. Прямые страницы vs модалки

- Комната — постоянный полный экран.
- Настройки сообщения/комнаты — modal task sheet.
- Работа с диалогами — sheet, при глубоком чтении отдельный layout внутри modal/tab; самостоятельный route остаётся deep-link fallback.
- Проверка документа и AI Workspace — **в первую очередь sheet** из комнаты, отдельный URL технически сохраняется для bookmarks/no-JS. В UI не изображать их новыми независимыми продуктами.
- Полноэкранный аккаунт/история остаются допустимыми страницами (пользователь может попасть туда извне), но единый header/back и surface system обязательны.

---

## 7. Пошаговая UX-спецификация критических экранов

### 7.1. Чат `/rooms/:id`

**Оставить:** текущие bubbles, side rail, avatars, emoji/reactions, media, translation original, reader anchors, быстрый composer.  
**Сделать:**

1. Canvas комнаты `--sd-canvas`, rail `--sd-shell`, bubbles `--sd-bubble-*`, лёгкая тень; убрать видимые декоративные разделительные линии.
2. Заголовок комнаты: имя, число участников (аватары небольшим stack), защищённость, онлайн/connection status — максимум одна компактная мета-строка.
3. Входящее сообщение: readable `15/16px`, padding `11px 14px`, line-height 1.5, `max-width: min(76%, 640px)` desktop, до `90%` mobile. Исходящее — отдельный оттенок, читаемая типографика и источник без лишних badges.
4. Action hover bubble — небольшое overlay-поле, не постоянное «облако» кнопок.
5. Reply/translation/original — компактные disclosures, не уменьшать текст оригинала до нечитаемого.
6. Composer поля: subdued 1px line, keyboard focus 2px; Ai Send/Manual Send не ломать, пока не прошёл функциональный рефакторинг по новому MVP.
7. На мобильном: список комнат выезжает drawer, но не перекрывает composer при открытой клавиатуре; возможность вернуться свайпом/стрелкой без потери draft.

### 7.2. «Настройки сообщения» (текущий `#ai-draft-panel`)

**Above the fold:** заголовок «Настройки сообщения», 2–3 плитки часто используемых пресетов + «Все стили», поле/preview, primary action.  
**Раскрывается по потребности:** тон, язык, размер, emoji, инструкции, расширенные источники, детали приватности и стоимости.  
**UI запрет:** крупные disabled-карточки на одну треть экрана, шесть одинаковых плиток всегда и длинная политика вместо действующей кнопки.  
**Функционально:** сохранить независимые ручной и AI inputs, ability undo, request explicit-approval, cost disclosure, source-review, preview, save history.

### 7.3. «Настройки комнаты» (текущий `#ai-room-settings`)

**Компоновка:** компактное summary карточки с текущим режимом `Универсальный / AI Answer / Русский` → карточка «Цель беседы» → стиль/язык → знания/файлы → разрешения → автоматизация → «Подробнее».

- Отдельные per-account и per-room настройки остаются раздельными. Не путать язык UI, язык входящего перевода и язык отправляемого ответа.
- Пресеты «Личное/Бизнес/Знакомства/Разработка» — уже есть; **не заставлять выбирать профессию** для работы базовых AI-режимов.
- На карточке Auto Reply показывать **фактическую** готовность и причину блокировки, не выдуманный AI-рейтинг.
- История редакций room instructions остаётся рабочей и доступной через disclosure.
- Технические детали ACL/consent не скрывать от пользователя полностью: краткий статус и «Подробнее» рядом.

### 7.4. «Работа с диалогами»

**Единый экран:** сверху «Выберите сообщения», табы `Все / Поиск / Участники / Период`, ниже карточки исходных сообщений с avatar + speaker + date + excerpt + toggle. `Выбрать доступные` — один тумблер выбора **в рамках текущей разрешённой выборки**, а не невидимый экспорт всей базы.

**Следующий шаг после выбора:** закреплённая полоска `Выбрано N → Продолжить`, операции-карточки `Итоги`, `Кратко`, `Действия`, `Хронология`, `Документ`, `Сравнить`, `Экспорт`; остальные операции через `Ещё`. Созданный результат — сохраняемый, именованный черновик с версией и ссылками на разрешённые источники. Изменение прав или удаление сообщения инвалидирует устаревшие исходные данные согласно существующей модели доступа.

**Существующее переиспользовать:** `ConversationCoverageSnapshotV2`, `ConversationEvidenceSearchV1`, `SourceSelection`, `AiDeliverable`, revisions, `.md/.txt` exports. Не считать lexically matched историю полноценным RAG или доказательством факта.

### 7.5. «Проверить документ» `/rooms/:id/ai/deliverable-review` — P0 редизайн

**Текущий корень:** `app/views/room_ai_deliverable_reviews/new.html.erb`; публичная Rails-страница с английскими литералами.  
**Новый UX:** один `SDTaskSheet`, не новая сложная полноэкранная страница.

**Шаг 1 — Результат (default visible)**
- Header: `← | Проверить документ | [⋯]`; ниже одна строка `На основе X разрешённых сообщений`.
- Карточка редактора с реально заполненным документом, изменяемым text area, внешне как редактор в чате.
- Действия в sticky footer: `Продолжить проверку` (primary), `Сохранить черновик` (secondary).

**Шаг 2 — Проверка утверждений**
- Вверху progress `Проверено N из M`, одна текущая карточка statement вместо длинного «документа с формой на 3 экрана».
- Каждое утверждение: excerpt, ссылка M33, compact `Подтверждено / Предположение / Неизвестно / Спросить` (локализованная семантика прежних choices, без изменения backend mappings).
- Дополнительные сведения и source history — по клику, не постоянно.
- `Назад`, `Следующее`, `Пропустить` с предсказуемым сохранением промежуточного выбора (только если реально поддержано; иначе честное предупреждение до выхода).

**Шаг 3 — Сохранить / Сравнить**
- Сводка нерассмотренных фактов, имени документа, версии, источников.
- Основная кнопка `Сохранить черновик`; вторично `Сравнить редакции`, `Экспорт`. Не обещать общее согласование — сервер пока поддерживает личные review-состояния и saved draft, а не quorum.

**Техническая стратегия:** сначала перевести ERB через `t('ui.document_review...')`, затем сделать модальный presentation wrapper, затем убрать дублирование редактора и длинного документа только после UI acceptance. Сохранить исходный POST/ACL, GET fallback и workflow сохранения/версий.

### 7.6. AI Workspace `/rooms/:id/ai` — P0 редизайн

- Использовать текущий серверный маршрут как deep link/fallback; при открытии из чата показывать `SDTaskSheet`.
- Заголовок: «AI-инструменты»; первая крупная карточка **«Что хотите сделать?»**, затем до 4 задач: `Подготовить ответ`, `Сделать итоги`, `Создать документ`, `Работа с источниками`.
- Основное действие доступно/disabled с понятной причиной. Разрешения и стоимость показывать в кратком статусе, подробности — в аккордионе.
- Недоступные по среде фичи не показывать как большие пустые карточки; использовать короткие строки состояния.
- Источники и consent recheck остаются неизменными на backend.
- Все строки/aria/ошибки I18n; текущая англоязычная «AI Workspace» как самостоятельный заголовок на RU интерфейсе запрещена.

### 7.7. Профиль и настройки `/users/edit`

- Карточка аватара/имени; карточка безопасности; персональные AI defaults; приватность/уведомления. Сохранить текущие формы и проверки пароля.
- Тематическая индикация сохранения без яркого ring вокруг любого focused input; focus-visible всё равно заметный.
- Настройки AI имеют `источник: аккаунт / комната`, explain inheritance под details.
- Кнопки действий не дублировать в каждой секции без контекста; формы, которые сохраняются раздельно, явно маркировать.
- Автоматически не открывать все разделы с описаниями при входе.

### 7.8. «События и история» `/notifications`

- Уже имеющийся поиск/фильтры не ломать. «События» и «История переписок» — компактные card lists.
- Строка события: avatar **отправителя** (если есть), инициатор+текст, время, маленькая иконка типа события, action/chevron.
- Прозрачный пустой state с одним CTA; не дублировать текст «история»/«найти» в четырёх соседних заголовках.
- Mobile: фильтры через horizontal scroll chips/compact select, без второго горизонтального скролла контента.
- Строки имеют 44px hit area, действия с клавиатуры.

---

## 8. Responsive / mobile-first контракт

### 8.1. Breakpoints (проектные)

| Ширина | Режим | Контент |
|---|---|---|
| `320–359px` | Small phone | Одна колонка, compact header, полноэкранная модалка, labels сокращены, touch 44px |
| `360–599px` | Phone | Одна колонка, 2-column presets лишь при достаточной ширине карточки |
| `600–899px` | Tablet / small landscape | Две колонки settings при читабельной ширине, stacked task flow |
| `900–1199px` | Desktop compact | Rail + chat, modal с 2–3 колонками cards |
| `>=1200px` | Desktop | Rail + chat, centered 1040/1120 sheets, max content width |

Реальные legacy breakpoints `360/390/420/480/540/600/767/920/1023px` сейчас существуют; переводить их на новую сетку **только компонентными изменениями**, не единым удалением media queries.

### 8.2. Обязательные проверки

- 320, 360, 390, 430, 600, 768, 1024, 1440, 1920 CSS px; масштаб браузера 100% и 200%.
- `env(safe-area-inset-bottom)` для composer и sticky modal footer.
- На mobile touch ни один инструмент не появляется *только* на hover.
- Клавиатура не закрывает composer или action; использовать `100dvh` с fallback и учитываемым viewport resize.
- Один основной vertical scroll в модалке; не создавать «скролл в скролле» без реальной необходимости.
- RTL-ready layout API (`margin-inline`, `inset-inline`, логический порядок) даже если в R1 поддерживаются RU/EN/HY/ES.

---

## 9. I18n — обязательно для каждой страницы/состояния

**Текущие локали интерфейса:** `ru`, `en`, `hy`, `es`.  
**Язык интерфейса не равен языку переписки и не равен языку переводчика.**

1. Статические подписи/описания/aria/title/tooltip/empty state/error/success/meta — только `I18n.t` / `t(...)` или локализованные Stimulus copy values.
2. Новые namespaces: `ui.ai_message`, `ui.ai_room`, `ui.dialogue_tools`, `ui.document_review`, `ui.ai_tools`, `ui.design_system` по необходимости. Не захламлять `ui.en.yml` тысячей неструктурированных ключей.
3. Исправить hardcoded English на `room_ai_deliverable_reviews/new.html.erb`, `room_ai_workspaces/show.html.erb`, `room_ai_deliverables/index/show.html.erb`, shared error dialogs и связанных action labels; выделить весь пользовательский копирайт, не только `<h1>`.
4. Переводы должны объяснять действия простыми словами, без «source inventory», «H4», «workflow», «provider gateway» в основном UI. Технический жаргон остаётся в `Подробнее` для разработчиков.
5. Поддерживать pluralization, `count`, дата/время/локаль, charset/Unicode, длинные армянские слова и переноcы, отсутствие жестких фиксированных ширин под русский.
6. При смене языка внутри модалки переводить текущий UI/статусы без потери draft/selection.
7. Системный тест на RU/EN/HY/ES: ни один показанный документ/AI Workspace не содержит английские обязательные labels в RU. Проверка `I18n.available_locales`, missing keys, overlays, aria labels, no «translation succeeded» на fallback.

---

## 10. Accessibility и обязательные UX safeguards

**Цель:** WCAG 2.2 AA для основных сценариев; AAA-пункты — ориентир при реализации focus. Стандарты: text 4.5:1, large 3:1; non-text component state 3:1, target minimum 24×24 AA (лучше наш стандарт 44×44), keyboard focus visible, semantic dialogs/accordion, robust zoom.

**ЗАПРЕЩЕНО ради эстетики:**

- `outline: none` без эквивалентного чёткого `:focus-visible`.
- Иконка без accessible name / `title` как единственный доступный label.
- Невидимые панели, остающиеся в Tab order.
- Скрывать меню при overflow, если keyboard navigation не может к нему добраться.
- Тонкий декоративный border как единственный признак поля или состояния.
- Результат AI без признака generated/кто отправил, ложное «согласовано» или «готово».
- Текст ошибки только цветом без текстового содержания.
- Скрытые непроверенные исходники/вложения через косметические «reviewed» badges.
- Непроверенный auto-translate без показа оригинала и fallback.
- Автоотправка или дорогостоящий API из UI-анимации, `hover`, `focus`, `connect()` или optimistic click другого назначения.

**Совместимость:** Chrome desktop, Firefox desktop, Safari/Chrome mobile, keyboard-only, screen reader smoke, high contrast/forced colors, reduced motion.

---

## 11. Архитектура безопасного внедрения в текущем Rails приложении

### 11.1. Файлы и правила ответственности

```text
app/assets/stylesheets/
  signal_deck_tokens_v2.scss          # единая семантика dark/light, theme adapter
  signal_deck_primitives_v2.scss      # card/button/field/icon/avatar/switch/chip
  signal_deck_motion_v2.scss          # durations, elevation and reduced motion
  signal_deck_modal_v2.scss           # task sheet, header/foot, nested scroll
  signal_deck_message_v2.scss         # только chat bubbles/composer geometry
  signal_deck_screen_migrations.scss  # временные точечные page adapters
  application.bootstrap.scss         # import order (контролируемый)

app/helpers/
  signal_deck_helper.rb              # расширить, НЕ заменить icon allowlist
  signal_deck_components_helper.rb   # новые helper wrappers — при необходимости

app/javascript/controllers/
  theme_controller.js                # сохранить, не создавать независимый theme store
  ui_select_controller.js            # сохранить native-backed custom popup
  ai_draft_controller.js             # сохранить функциональность, менять UI по срезам
  sd_task_sheet_controller.js        # новый, если переиспользовать существующий нельзя

app/views/shared/
  _sd_card.html.erb
  _sd_icon_tile.html.erb
  _sd_avatar.html.erb
  _sd_task_sheet.html.erb
  _sd_field.html.erb

config/locales/
  design_system.{ru,en,hy,es}.yml    # только общие элементы UI
  ai_message.{ru,en,hy,es}.yml
  document_review.{ru,en,hy,es}.yml
  ai_tools.{ru,en,hy,es}.yml
```

Это **план структуры**, не существующие файлы. Не добавлять папки/partial без необходимости: прежде найти действующий эквивалент и заменить шаблон точечно. Существующие partial и классы `.sd-*` можно сохранить с новыми токенами.

### 11.2. CSS порядок и предотвращение cascade drift

**Базовый принцип:** один источник цвета — map/mixin + `--sd-*`. На переходе новый файл импортируется после предыдущих token declarations, но до самых конкретных новых компонентных override. Нельзя сразу удалить `signal_deck_refinement.css` / `signal_deck_accessibility.scss` — там не только оформление, но и функционально важные компоновки, фокус, мобильные фиксы.

**Рекомендованная миграция:**

1. Извлечь токены из `signal_deck.css`, `signal_deck_refinement.css` и обеспечить один сгенерированный набор dark/light/system. Проверить computed styles в Chrome для 10 базовых элементов.
2. Создать примитивы, не меняя classes/class API; старые страницы на переходе продолжают работать на alias tokens.
3. Перевести 1 экран и его конкретные selectors, удалить только заменённые hardcoded declarations; визуально сравнить до/после.
4. Убирать повторные `!important` после visual acceptance, не усугублять селекторную войну новыми `#id .parent div`.
5. Проверить, что theme cycle через `theme_controller.js` не создаёт смешанной палитры и no-flash-of-incorrect-theme при Turbo navigation.

### 11.3. Модальные маршруты Rails/Turbo

- Основной `GET /rooms/:id/ai/deliverable-review` по-прежнему обслуживается и без JS, с серверным ACL.
- Из комнаты переход — fetch/Frame into existing modal outlet с `SDTaskSheet` и `aria-labelledby`.
- URL/durable deep link сохраняется через History API/Turbo navigation **без** нарушения back stack; при закрытии вернуть previous room state.
- Переход внутри review не должен заново загружать комнату или стирать composer draft. При недоступности JS — обычный безопасный рендер.
- Нет запроса к provider при открытии sheet; форма POST, разрешения и бизнес-логика остаются прежними.

### 11.4. Component contracts для тестирования

- Каждый новый компонент должен иметь: HTML/ERB partial, CSS token use, aria/state mapping, native keyboard behavior, light/dark screenshots, mobile acceptance, reduced motion behavior, locale test.
- CSS selector scope: `.sd-app .sd-*` или component root; не `input {}` и не глобальный `::-webkit-scrollbar` за пределами приложения.
- JS: данные из сервера — как untrusted; HTML не строить из текста сообщений через `innerHTML`; сохранить существующие provenance/ACL mechanisms.
- Не переводить на React/Vue ради UI refactor. Hotwire/Stimulus достаточно; native `<dialog>` и HTML `<details>` уже доступны.

---

## 12. Список «разрешено / необходимо / запрещено»

| Категория | НЕОБХОДИМО | РАЗРЕШЕНО | ЗАПРЕЩЕНО |
|---|---|---|---|
| Цвет | Только semantic `--sd-*` | `color-mix` на базе token | Случайные hex в компонентах, контрастный неон |
| Карточка | Тональный слой, 16px radius | Hover lift -2px | Декоративные видимые рамки по всей странице |
| Поле | 1px subdued border + focus-visible | Borderless tonal input если ясно обозначено | Яркая glow-окантовка на любом click |
| Иконка | `sd_icon` / 24-grid | Двухцветный SVG detail | Разные icon packs и emoji вместо рабочих пиктограмм |
| Аватар | User photo/fallback | Stack avatars в шапке | Generic icon вместо идентичности пользователя |
| Селект | Кастомный `ui_select` | Native semantic fallback без JS | Браузерный popup как основной enhanced UI |
| Модалка | Back/Close/Esc, focus, preserved draft | Full-screen mobile | Бесконтрольный новый full page на вторичное действие |
| Тексты | Ясные labels, I18n | Details/accordion для справки | Простыни политик над основным CTA, непереведённые English |
| Motion | 120–300ms, reduced motion | Soft hover, short slide/opacity | Перманентная анимация, twitch, gratuitous parallax |
| Скролл | Thin, consistent, native accessibility | Overlay scrollbar OS | Глобальная белая 10px полоса, `display:none` обязательного скролла |
| Mobile | 320px no overflow, 44px hit | Collapsible menus | Hover-only действия, 7+ иконок подряд |
| AI | Реальное состояние, cost/consent, provenance | Compact readiness | Ложные проценты качества, скрытый платный запрос |

---

## 13. Приоритетный roadmap внедрения (без повторения готовых функций)

### D0 — инвентаризация и visual baseline — P0

**Действия:** точные screenshots в обеих темах + 320/390/768/1440; зафиксировать CSS import order, hardcoded colors, `!important`, компоненты; проверить локальный modified `db/schema.rb` **без изменения**.  
**DoD:** список затрагиваемых components/routes и эталонные before screenshots. Никаких новых миграций и деплоев.

### D1 — единая палитра, поля, shadows, scrollbars — P0

**Действия:** токены, dark/light/system, old token aliases, поля с subdued border, global scrollbar fix, focus-visible QA, приоритеты.  
**DoD:** app shell/композер/инпуты/системные панели не отличаются случайным цветом; theme cycle работает без F5; нет XSS/ACL/JS regressions.

### D2 — reusable primitives, avatars, two-tone icon system — P0

**Действия:** расширить `SignalDeckHelper`, создать только недостающие обёртки, применить к room list, messages, notifications, settings.  
**DoD:** все участники на изменённых экранах представлены avatar/fallback; icon size consistent, aria labels, 44px targets.

### D3 — «Настройки сообщения» и «Настройки комнаты» — P0

**Действия:** переименовать UI captions (не серверные сущности); сократить presетные плитки, details; всё равно сохранить AI/consent/settings logic; сохранить state across panel switch.  
**DoD:** открыть → увидеть нужный CTA в первом viewport → настроить → закрыть → draft сохранён; не происходит платных вызовов автоматически.

### D4 — AI Workspace и «Проверить документ»: i18n + task-sheet — P0

**Действия:** сначала полностью локализовать, затем визуально преобразовать в modal task flow. Использовать существующие GET/POST, results, versions, export.  
**DoD:** RU/EN/HY/ES, active modal back, Esc, focus return, document draft/compare/save unchanged; no-JS deep link, mobile screen 320px.

### D5 — «Работа с диалогами» и visual navigation — P1

**Действия:** собрать уже существующие Coverage/Evidence/Document actions в единую panel с коротким списком задач; не строить параллельно «новый RAG».  
**DoD:** базовая выборка, поиск, review, create document без потерянных ссылок/источников; consistency в обоих themes.

### D6 — polish главного чата, страницы событий и аккаунта — P1

**Действия:** shallow depth bubbles, hover, avatars, refined empty states, responsive spacing, native dropdown audit, theme light QA.  
**DoD:** chat remains fast at 100+ messages; no scroll jumps, realtime/translation/attachments work; visual parity light/dark.

### D7 — design-system gates перед Railway MVP — P0 release gate

**Действия:** CI+browser tests, a11y, two-user live, localhost and independently deployed UI smoke, cleanup obsolete CSS only once covered.  
**DoD:** main flows both themes, no critical untranslated page, no keyboard/modal traps, release SHA green, no accidental paid calls. Отдельное согласование бюджета/деплоя Railway и backup/recovery не отменяется дизайн-этапом.

**Параллельный продуктовый план AI:** разработка динамической AI Answer/Beautify кнопки, контекстной генерации, целей и управляемых автоответов независима от чисто визуального рефакторинга. Дизайн-система задаёт их UI-контракт, но **не является доказательством реализации backend**.

---

## 14. Обязательная матрица приёмки

### Визуальная

- [ ] Dark и light на `/rooms/:id`, `/notifications`, `/users/edit`, `/rooms/:id/ai`, `/rooms/:id/ai/deliverable-review`, `#ai-draft-panel`, `#ai-room-settings`.
- [ ] Светлая тема вручную проверена (скриншотов в текущем аудите нет).
- [ ] Нет несогласованных literal hex и яркого outline у полей; keyboard focus виден.
- [ ] Неподвижный/hover/active/disabled/selected/loading/error/empty state для каждого изменённого компонента.
- [ ] Icon style, tile size, radius и avatar fallback согласованы во всех ролях.
- [ ] Scrollbar аккуратный в chat, modal, selected sources, document editor; нет квадратной 10px полосы.
- [ ] Поверхности читаемы, сообщения имеют контролируемую глубину; текст не меньше утверждённой шкалы.

### Поведенческая

- [ ] Modal opening, close, Escape, Back, deep-link, restore focus, preserve draft/attachments/scroll.
- [ ] Custom selects mouse/touch/keyboard, no-JS fallback.
- [ ] 320/360/390/430/600/768/1024/1440/1920 + zoom 200%.
- [ ] All actions accessible without hover; `prefers-reduced-motion` respected.
- [ ] RU/EN/HY/ES full interface copy, errors, labels and aria, long texts and language switching while modal open.
- [ ] Real two-user messaging without F5, attachments access, edit/reply/reactions, translation+original, context consent, no data leak.
- [ ] Disabled AI/automation has truthful reason; no silent generation or Send.
- [ ] Existing server-side permissions, review state, document versions, saved drafts and cost constraints unchanged.
- [ ] CI/security/Docker/production image checks green at *exact* release SHA.

### Критерии остановки изменения

Если одно изменение ломает версионирование документа, формирование ручного Send, AI provenance, доступ к вложениям, разрешения участников, realtime или сохранение draft — откатить **этот UI срез** через версионируемый коммит. **Не делать** destructive DB reset, `git reset --hard` пользовательской локальной ветки, очистку volumes или слепой restore schema. Сохранять owner-local изменённый `db/schema.rb`.

---

## 15. Мастер-задание для следующего инженерного чата

> Ты работаешь над существующим `TheGor-365/turbo_chat`, Ruby on Rails / Hotwire, ветка `feat/security-baseline-2026-11-03` (последний проверенный на момент документа SHA `f4ae7bc`; **сначала перепроверь актуальный HEAD, CI и рабочее дерево**). Источник дизайн-правил — этот документ `TURBO_CHAT_SIGNAL_DECK_DESIGN_SYSTEM_V2_2026-11-17.md`; продуктовый ориентир — универсальный AI-first messenger с Beautify, AI Answer, Auto Reply. Действуй узкими вертикальными UI-срезами D0→D7. Перед правкой читай существующий partial, Stimulus, styles и tests; не создавай дубль существующего механизма. Каждый срез: минимальный diff → Rails+Chrome+security+Docker+production-image CI → владелец локально проверяет screenshot. Не мерджи `main`, не деплой Railway, не запускай платный API и не трогай локальные данные без отдельного разрешения. Все цвета — semantic tokens, обе темы; интерфейсы RU/EN/HY/ES; все мобильные ширины; удобная modal/navigation; focus/accessibility; avatars/icons. После каждого среза дай: изменённые файлы, exact SHA, CI/acceptance evidence, что не проверено, 1–3 шага владельцу.

### Следующее непосредственно рекомендуемое действие

**D0/D1 — не полная переделка.** Начать с `signal_deck_tokens_v2.scss` и **глобального исправления scrollbar/input focus только под `.sd-app`**, отдельно проверить Chat/Account/Modal dark+light. Не начинать с огромной «Проверить документ» до стабилизации токенов и модального паттерна.

---

## 16. Факты, гипотезы и ссылки

### Подтверждено исходниками на SHA `f4ae7bc`

- Текущие цвета/темы: [`signal_deck.css`](https://github.com/TheGor-365/turbo_chat/blob/f4ae7bc/app/assets/stylesheets/signal_deck.css) и [`theme_controller.js`](https://github.com/TheGor-365/turbo_chat/blob/f4ae7bc/app/javascript/controllers/theme_controller.js).
- Слой чат-компоновки и устаревший scrollbar: [`chatroom.css`](https://github.com/TheGor-365/turbo_chat/blob/f4ae7bc/app/assets/stylesheets/chatroom.css).
- Дополнительные chat/AI визуальные слои: [`signal_deck_refinement.css`](https://github.com/TheGor-365/turbo_chat/blob/f4ae7bc/app/assets/stylesheets/signal_deck_refinement.css), [`signal_deck_accessibility.scss`](https://github.com/TheGor-365/turbo_chat/blob/f4ae7bc/app/assets/stylesheets/signal_deck_accessibility.scss), [`chat_ui_consistency.scss`](https://github.com/TheGor-365/turbo_chat/blob/f4ae7bc/app/assets/stylesheets/chat_ui_consistency.scss).
- Кастомный селект: [`ui_select_controller.js`](https://github.com/TheGor-365/turbo_chat/blob/f4ae7bc/app/javascript/controllers/ui_select_controller.js) и [`chat_signal_select.scss`](https://github.com/TheGor-365/turbo_chat/blob/f4ae7bc/app/assets/stylesheets/chat_signal_select.scss).
- First-party icons: [`signal_deck_helper.rb`](https://github.com/TheGor-365/turbo_chat/blob/f4ae7bc/app/helpers/signal_deck_helper.rb).
- Не полностью локализованные AI/Review страницы: [`room_ai_workspaces/show.html.erb`](https://github.com/TheGor-365/turbo_chat/blob/f4ae7bc/app/views/room_ai_workspaces/show.html.erb), [`room_ai_deliverable_reviews/new.html.erb`](https://github.com/TheGor-365/turbo_chat/blob/f4ae7bc/app/views/room_ai_deliverable_reviews/new.html.erb).
- Screenshots предоставлены владельцем 17.11.2026, 15 desktop PNG. Скриншоты показывают внешний вид, но не подтверждают работу неоткрытых контролов или светлой темы.

### Внешние ориентиры (источники, не слепое копирование чужого дизайна)

- [W3C WCAG 2.2](https://www.w3.org/TR/WCAG22/) — contrast, focus, target size.
- [W3C APG: Modal Dialog](https://www.w3.org/WAI/ARIA/apg/patterns/dialog-modal/) — Escape, фокус и настоящая модальность.
- [W3C APG: Accordion](https://www.w3.org/WAI/ARIA/apg/patterns/accordion/) — keyboard, `aria-expanded` и управление скрытым контентом.
- [MDN: `prefers-reduced-motion`](https://developer.mozilla.org/en-US/docs/Web/CSS/Reference/At-rules/%40media/prefers-reduced-motion) — адаптация движения.
- [MDN: `scrollbar-width`](https://developer.mozilla.org/en-US/docs/Web/CSS/Reference/Properties/scrollbar-width) и [Google Chrome: Scrollbar guidance](https://developer.chrome.com/docs/modern-web-guidance/guides/visual-design/customize-scrollbar-color-and-thickness).
- [Material 3 color roles](https://developer.android.com/develop/ui/compose/designsystems/material3) — семантические поверхности, tonal elevation, а не много бордюров.
- [NN/g Dark Mode](https://www.nngroup.com/articles/dark-mode-users-issues/) — необходимость тонально разделять слои и проверять читаемость.

### Что не следует утверждать без новых тестов

- Не утверждать «WCAG AA полностью пройден» по этой спецификации: измерены только некоторые непрозрачные пары, нет полного теста интерфейса.
- Не утверждать, что новый дизайн уже в GitHub или Railway: это **файл стандарта**, никаких production-изменений он сам не выполняет.
- Не утверждать, что светлая тема проверена по скриншотам: показана только тёмная.
- Не утверждать, что AI Answer/Auto Reply или универсальный перевод уже закончены: это отдельный план функциональной разработки.

---

**Definition of Done для дизайн-системы:** пользователь открывает любой модуль Turbo Chat и без текста-инструкции понимает его главное действие; обе темы воспринимаются как один бренд; любое открытое окно можно понятно закрыть и вернуться в прежний контекст; компоненты предсказуемы на desktop/mobile; backend-логика и пользовательские данные сохранены.