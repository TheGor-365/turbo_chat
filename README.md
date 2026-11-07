# Turbo Chat — Rails messenger (work in progress)

An educational Ruby on Rails / PostgreSQL / Redis / Turbo chat application.
Current branch: `feat/security-baseline-2026-11-03` ([draft PR #2](https://github.com/TheGor-365/turbo_chat/pull/2)).
**Not production-ready.** Never place real client conversations or credentials in the demo.

## Быстрый локальный запуск / local preview

**Requirements:** Docker Engine with Compose plugin, Git; Linux/macOS.

```bash
git fetch origin
git switch feat/security-baseline-2026-11-03 || git switch --track origin/feat/security-baseline-2026-11-03
git pull --ff-only
docker compose up --build
```

Open **http://127.0.0.1:3000**. Create two test accounts in separate browsers
to check room membership, messages, uploads, editing/deletion and realtime.
Local PostgreSQL and Redis run in isolated containers; only port 3000 is
exposed, bound to localhost. Uploaded files are stored in `storage/` on the
local machine. No Railway credentials are required.

To stop, press Ctrl+C, then `docker compose down`. **Do not run
`docker compose down -v` unless you intend to delete your local database
and node_modules volumes.** For background launch:
`docker compose up -d --build` and `docker compose logs -f web`.

For native Linux setup with asdf, PostgreSQL, Redis and Yarn, see
[docs/LOCAL_DEVELOPMENT_RU.md](docs/LOCAL_DEVELOPMENT_RU.md).

## Stack

- Ruby 3.4.12 / Rails 8.1.4 / PostgreSQL / Redis
- Hotwire Turbo/Stimulus, Bootstrap 5, Sass, Yarn Classic
- Devise authentication, membership-scoped WebSocket streams and downloads
- CI: Rails Minitest, Redis integration, Chrome system acceptance, security audit

The Compose image is **development-only**, runs with local test credentials,
and is neither hardened nor configured for a public deployment. Staging and
production storage, backup, email delivery and operational safeguards remain
separate release gates.
