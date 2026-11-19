# Checkpoint 2026-11-04 — repeatable local preview

Local development now has a dedicated Dockerfile.dev / Compose stack
with Ruby 3.4.12, Node 24, PostgreSQL 16, Redis 7, Rails and asset watchers.
Host Rails port is bound only to 127.0.0.1; database and Redis ports remain
internal. Existing main branch, Railway and any remotely deployed database
were not modified.

Native Linux asdf users can install Ruby 3.4.12 from the committed
.tool-versions; README and docs/LOCAL_DEVELOPMENT_RU.md document both routes.
Environment-specific PG and REDIS_URL configuration is now supported in
development without changing preexisting local defaults. Local database
password in compose.yaml is a public test-only value, never a production
secret.

Docker build / real HTTP boot verification is a separate CI task, and cannot
be marked PASS until its GitHub Actions run succeeds. Current Minitest and
browser tests also need to pass on this new branch head.
