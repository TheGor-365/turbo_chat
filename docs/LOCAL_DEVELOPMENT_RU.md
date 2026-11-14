# Turbo Chat — локальный запуск на Linux Mint

Актуально на 2026-11-04. Репозиторий: https://github.com/TheGor-365/turbo_chat
Ветка: `feat/security-baseline-2026-11-03`. Не запускай устаревший `main`
для проверки новых функций.

## 0. Безопасно перейти на рабочую ветку

```bash
cd /путь/к/turbo_chat
git status --short
git fetch origin
```

Если `git status --short` не пуст, НЕ выполняй `git reset --hard`,
`git clean` или `stash` автоматически: сначала разберись с собственными
локальными изменениями. При чистом дереве:

```bash
git switch feat/security-baseline-2026-11-03 || git switch --track origin/feat/security-baseline-2026-11-03
git pull --ff-only
git branch --show-current
```

Ветка требует **Ruby 3.4.12**, исходный `main` требует **3.1.2**.
Установленная у тебя Ruby 3.4.7 не подходит **ни под одну** точную версию
в этих Gemfile. Изменять Gemfile обратно на 3.4.7 не нужно.

## 1. Рекомендуемый вариант: Docker Compose

Проверить Docker Engine и Compose:

```bash
docker --version
docker compose version
```

Запустить PostgreSQL 16, Redis 7, Rails 8, JS/CSS watchers:

```bash
docker compose up --build
```

Открыть http://127.0.0.1:3000. Если порт 3000 занят, измени **только**
левую часть в `compose.yaml` с `127.0.0.1:3000:3000` на
`127.0.0.1:3001:3000` и открой 3001.

Для постоянного просмотра:

```bash
docker compose up -d --build
docker compose logs -f web
```

Остановка: `docker compose down`. Именованный volume БД сохраняется.
`docker compose down -v` удаляет данные — **не использовать для
обычного выключения**.

Диагностика:

```bash
docker compose ps
docker compose logs --tail=120 web db redis
docker compose exec web bin/rails about
```

При переключении Git-ветки с Rails/DB-миграциями запуск
`bin/rails db:prepare` внутри контейнера происходит автоматически.
Для ручного вызова:

```bash
docker compose exec web bin/rails db:prepare
```

Compose не публикует PostgreSQL и Redis в сети, а приложение привязано
к `127.0.0.1`. Пароль БД — только для локального контейнера, не production.
Внешние реальные данные не загружать.

## 2. Альтернативный вариант: нативная установка через asdf

Не требуется, если Docker Compose уже работает. Если хочешь запускать
Rails непосредственно из Linux Mint:

```bash
asdf plugin list
asdf install ruby 3.4.12
ruby -v
bundle install
```

`.tool-versions` в этой ветке фиксирует `ruby 3.4.12`. Если asdf Ruby
plugin не установлен — установи его отдельно. Нужны локально работающие
PostgreSQL и Redis; база `turbo_chat` и пользователь `postgres` должны
быть доступны, либо выставь переменные `PGHOST`, `PGPORT`, `PGUSER`,
`PGPASSWORD` (не коммитить реальные пароли).

JS/CSS: Node.js 24 + Yarn 1.x (в CI именно Node 24). Запустить:

```bash
yarn install --frozen-lockfile
bundle exec rails db:prepare
bin/dev
```

`bin/dev` запускает Rails и наблюдателей JS/CSS; если `foreman`
не установлен, старый скрипт может предложить установить его.
Сайт: http://localhost:3000.

## 3. Проверка вручную

Открой две сессии (например Chrome обычный + приватное окно), создай
двух фиктивных пользователей. Проверь:
1. регистрация и вход;
2. вступление в общую комнату, отправка текста и картинок;
3. получение второго сообщения без обновления страницы;
4. редактирование и удаление своих сообщений;
5. невозможность редактировать чужое сообщение.

Для автоматической проверки в Rails (нужна подготовленная test-БД):

```bash
docker compose exec -e RAILS_ENV=test web bin/rails db:prepare
docker compose exec -e RAILS_ENV=test web bin/rails test
```

Браузерные тесты Chrome запускаются в GitHub Actions; в обычном
Docker dev-образе Chrome не устанавливается.

**Ограничения:** локальная версия не является production, приватное
хранилище и резервирование на Railway не настроены; глубокая проверка
файлов, multiworker Redis и эксплуатационные проверки ещё в разработке.
