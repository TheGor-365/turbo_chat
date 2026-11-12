# Turbo Chat / Relay Workspace

**Статус:** кандидат для локальной демонстрации, ветка
[`feat/security-baseline-2026-11-03`](https://github.com/TheGor-365/turbo_chat/pull/2),
Draft PR #2. **Публичный demo, платные подписки, SLA и E2EE не подтверждены.**

## Назначение

**Turbo Chat** — обычный веб-мессенджер: личные переписки, публичные
комнаты, закрытые группы, сообщения и вложения, реакции, ответы,
уведомления, поиск, realtime. Для переписки AI не обязателен.

**Relay Workspace** — дополнительный слой: из разрешённой переписки
получить черновик клиентского брифа с источниками, сохранить версию,
внести правку, увидеть diff и явно скачать Markdown/TXT.
Это не автоматическое утверждение требований клиентом.

**Основной кейс:** фрилансер обсудил задачу с клиентом → создал черновик
Client Brief из допустимых выдержек → проверил формулировки →
сохранил v1 → отредактировал v2 → сравнил версии → скачал выбранную.
Сохранение не отправляет сообщение в комнату. Обработка приватного
контекста требует действующих согласий; платный AI — отдельного решения
и лимита. Межучастниковое одобрение/публикация ещё не реализованы.

## Стек

Ruby 3.4.12, Rails 8.1.x, PostgreSQL, Redis, Action Cable, Hotwire,
ERB, Bootstrap 5, Active Storage, Devise, Docker.
Тесты: Minitest, Chrome в двух независимых сессиях, Redis, security
audit, smoke и отдельная сборка production-образа. **Проверять на текущем SHA.**

## Локальный запуск без удаления данных

```bash
git fetch origin
git switch feat/security-baseline-2026-11-03 || git switch --track origin/feat/security-baseline-2026-11-03
git pull --ff-only
docker compose up -d --build
docker compose logs --tail=50 web
```

Открыть `http://127.0.0.1:3000`. Существующие сообщения,
локальные версии документов, `db/schema.rb`, `storage/` и Docker
volumes не очищать. Никакого `db:reset`, `db:drop`,
`docker compose down -v`, `git reset --hard`.

## Что ещё не готово

Публичный HTTPS/WSS, проверенный production backup/restore, внешний
email/reset, коммерческий биллинг, роли команд/клиентов, правовые
документы и подтверждённая безопасность клиентских данных.
Отдельный контейнер и Railway runbook подготовлены, но не означают,
что сервис уже запущен публично.

[Архитектура](docs/ARCHITECTURE.md) ·
[План Railway](docs/DEPLOY_RAILWAY.md) ·
[Кейс RU/EN](docs/RELAY_CASE_STUDY_2026-11-12.md) ·
[Checklist](docs/RELEASE_CHECKLIST.md).

Контакт для обсуждения инженерного кейса/пилота:
[GitHub TheGor-365](https://github.com/TheGor-365).
