# ADR — AI Workspace Gate 2A: room-scoped offline privacy review (2026-11-08)

## Evidence and product contract
The owner accepted Signal Deck Public/Private sidebar locally on Linux Mint after fast-forward `deca749..cdc2fdf`; PostgreSQL and Redis healthy, local `db/schema.rb` deliberately modified. Conversation history and media intact. Next agreed gate is *opt-in AI* with explicitly selected message scope, per-room ACL, provider contract, consent and budget. There is no approved provider, paid API, data-retention policy or cost budget.

## Decision and implementation
- Add a Signal Deck toolbar icon `sparkles` to an authenticated, currently authorized room. It opens `GET /rooms/:room_id/ai`, an honest **AI not configured** screen, labelled privacy/cost guardrails, operation selector (Summarize / Translate / Suggest reply), individual text-message checkboxes and read-only review.
- `POST /rooms/:room_id/ai/preview` only reviews explicit IDs from the current authorized room. `AiWorkspace::Scope` rechecks membership, validates operation, 1–8 unique decimal IDs (no global Message.find), rejects missing/cross-room and empty-text messages, orders by message chronology and truncates each at 750 Unicode characters. No attachment bytes, full-room auto-history, users list or auth email sent.
- `AiWorkspace::Gateway` is **fail-closed**: `configured? = false`, generation raises `ProviderUnavailable`. There is no adapter, outbound HTTP, provider SDK, ENV-key lookup, paid request, assistant bot user, persisted AI output or third-party access.
- No new DB tables/migrations and **no consent has yet been collected or persisted**. This is a *local preview of selected context*, not a real summarization, translation or AI response. The UI clearly labels this.
- Every GET/POST verifies actual membership (DM, invite-only group, joined public room); invalid/forged message IDs return only generic errors; no-store/no-sniff headers; the review POST is rate-limited. Default server-side selection is empty; the user must check each message.
- The UI inherits Signal Deck dark/light, icon-only entry, native form semantics, labelled scope, keyboard checkbox navigation, screen reader updates, and compact responsive workspace presentation.

## Next Gate 2B, requires explicit owner approval before external calls
1. Agree provider(s), Armenia/RF legal/payment availability, current data-retention terms and rate card; choose explicit daily/monthly cost caps and kill switch.
2. Design durable **per-room all-participant consent**, reauthorization and revocation using an ADDITIVE migration only after reviewing the owner's intentionally dirty local `db/schema.rb` and controlled backup. Explicitly scope each request to selected messages; attachments/RAG separately gated.
3. Implement provider adapter behind server-side gateway with metering, audit (no raw chat bodies in logs), cancellation, streaming where reliable, permission changes and failure handling; test fake adapter exclusively in test. Never silently enable the real provider.

## Boundaries and verification
Do not alter `main`, Railway, existing user projects, real provider credentials, billing, local PostgreSQL volumes or Active Storage. No data reset, no migration. Exact-head Rails/Redis/Cable/Chrome/Security/Docker CI required; owner-local browser screenshot acceptance pending.
