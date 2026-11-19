# Relay Workspace — portfolio case / Портфолио-кейс

As of 2026-11-12. Draft PR #2:
https://github.com/TheGor-365/turbo_chat/pull/2

## RU — Обсуждение → версионируемый документ

**Задача.** В переписке фрилансера и небольшой digital-команды
требования, решения и открытые вопросы перемешаны с бытовыми
сообщениями. Превратить их в проверяемый бриф вручную долго.
Коммерческий спрос на отдельный продукт пока **гипотеза**, а не
подтверждённая выручка.

**Решение.** На Ruby on Rails + Hotwire создан мессенджер с
разграничением личных/групповых переписок и необязательным Relay
Workspace. Локальный генератор формирует черновик Client Brief из
доступных разрешённых источников; человек проверяет утверждения,
сохраняет приватные immutable версии, сравнивает изменения и отдельно
экспортирует .md/.txt. Сохранение и экспорт не отправляют сообщение,
не подтверждают соглашение и не вызывают платный AI.

**Инженерные особенности.** PostgreSQL, Redis Action Cable,
двухбраузерные realtime-тесты, Devise, Active Storage через
авторизованные маршруты, consent/budget gate AI, source-linked
validation, CSRF и защита от чужого ID. Для сохранения H5 введена
нормализация CRLF → LF, чтобы тело версии, SHA-256 и экспорт совпадали.

**Подтверждения.** Владелец 12.11 локально проверил сохранение
Client Brief v1 и v2 и разницу **1 added / 1 removed / 12 unchanged**.
Это localhost, не публичное demo. Code/CI и production image требуют
проверки по актуальному SHA (ссылка на Actions в PR). Никаких
реальных клиентов, оплат, production restore и SLA не заявлено.

**Ограничения.** Approval другому участнику, полноценная production
эксплуатация и биллинг не выпущены. Проверки, citations и human
designation не доказывают истинность требований. Внешний pilot
возможен только после явной отдельной приёмки.

**CTA:** [Исходники и Draft PR](https://github.com/TheGor-365/turbo_chat/pull/2),
[профиль разработчика](https://github.com/TheGor-365).

## EN — Conversation to versioned deliverable

**Problem.** Freelancers and small content teams discuss scope in chat,
where requirements, opinions and unresolved questions become mixed.
Extracting a reviewable client brief is a manual coordination cost.
Product demand is still **a hypothesis**, not proven revenue.

**Solution.** An existing Rails/Hotwire messaging app was extended
with an opt-in document workflow: a local, bounded, source-aware Client
Brief draft; explicit private Save; immutable v1/v2 revisions; line diff;
and separate authorized Markdown/TXT export. Normal chat remains useful
without AI. No auto-send, hidden provider call or implied agreement.

**Engineering.** PostgreSQL for persistent data, Redis Action Cable,
Devise/room ACL and private media, CSRF, consent plus AI budget gates,
structured citation checks, reproducible Docker development CI and a
production-image **candidate**. H5 normalizes browser CRLF line endings
before storing and hashing a revision.

**Evidence.** Owner-local v1/v2/diff screenshots confirmed on 12 Nov 2026:
1 added, 1 removed, 12 unchanged. The Chrome/Redis, security,
Docker Compose and production image jobs must be checked on the
current commit before release. No public customer data, paid users,
live revenue or public uptime claims are made.

**Known limitations.** Cross-participant approval/share, production
backup/restore, real HTTPS/WSS demo and commercial onboarding remain
open. This is a portfolio-grade engineering release candidate, not
a certified production platform.

**Source:** [Draft PR #2](https://github.com/TheGor-365/turbo_chat/pull/2).
**Contact:** [GitHub profile](https://github.com/TheGor-365).

## Screenshot / walkthrough evidence still required

No synthetic screenshots should be represented as live product proof.
Capture real source UI only after current SHA is checked:
guest homepage, desktop and mobile DM/group, scoped context screen,
H4 Client Brief, H5 v1, edited v2, diff, explicit export/download.
Redact names, emails, message bodies and upload contents that are not
pure synthetic test data. Planned video: 60–120s, not yet recorded.
