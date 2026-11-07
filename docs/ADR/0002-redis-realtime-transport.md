# ADR 0002 — Redis for realtime fanout (2026-11-04)

## Context
- Rails 8.1 / Turbo Streams / PostgreSQL application has existing authorized
  `RoomMessagesChannel` and per-recipient stream names.
- Development and future production already configure the Redis
  ActionCable adapter; Redis is also used for distributed throttling.
- A shared backend is needed for live messages crossing app processes.
  PostgreSQL remains the source of truth for message history.

## Decision
Keep **Redis Pub/Sub as the transport for ActionCable**, rather than add
Solid Cable in this phase. This reuses the existing integration and
keeps a single known transport while a two-process transport acceptance
test is introduced. It is an architectural choice for the current
educational application, not a blanket claim that Redis is cheaper or
faster on every provider.

## Evidence
- Existing Chrome system test checks two browsers with the `async`
  adapter; it is NOT proof of cross-process realtime.
- New dedicated `REDIS_CABLE_INTEGRATION=1` Rails test config uses
  `adapter: redis`; test forks a separate OS process subscribed via a
  second Redis connection, publishes via `ActionCable.server.broadcast`,
  and validates the payload and worker exit status.
- Membership security remains covered separately in room-channel tests.

## Tradeoffs / open gates
- Redis Pub/Sub is ephemeral: lost connections miss events. Persisted
  PostgreSQL messages must be reloaded after reconnect. No durable
  offline notification or delivery guarantee is claimed.
- Connection pooling, reconnect, revocation and cross-worker browser
  sessions still need production-like validation at external HTTPS/WSS.
- Railway Redis pricing/resource count must be reviewed before purchase.
- Do not expose Redis ports publicly or reuse another project's Redis.
- Do not switch to Solid Cable without a separate migration/benchmark
  and an explicit ADR amendment.
