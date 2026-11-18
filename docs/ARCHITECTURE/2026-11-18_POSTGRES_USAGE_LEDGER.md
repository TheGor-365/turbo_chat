# PostgreSQL Usage Ledger — S6 foundational slice

Date: 2026-11-18. Status: standalone accounting code; **not wired to any provider**.

- Existing development-only file ledger is retained for the dev-only xAI services. No paid calls are moved to the database ledger without a separate reviewed provider gateway change.
- `AiUsageReservation` stores hashed actor-scoped UUID, room/user, purpose, UTC accounting periods, reserved/allocated/actual 1e-10 USD ticks, and state `reserved|uncertain|settled`. No raw API payloads or room history.
- `PostgresUsageLedger` serializes **all** reservation and settlement transactions with a PostgreSQL advisory transaction lock. A request ID is single-use forever. Default caps: $0.10/request, $0.30/user/day, $1/user/month, $1/room/month and $2/global/month, with user/global outstanding caps. All checks use committed PostgreSQL sums while holding the same lock.
- Provider timeout/unknown cost stays `uncertain`; never automatically release an unknown liability or retry a paid request. Settlements allow exact duplicate cost, reject conflicting amounts. Measured overage is persisted *before* BudgetExceeded is raised.
- Monthly/date buckets are UTC, but unresolved outstanding reservations continue to constrain future spending across periods.
- This ledger **does not grant** room-history consent, background processing, unattended Send or job execution. The future production gateway must reserve before any provider call, settle or mark uncertain, and revalidate ACL/consents, with no provider retries on uncertainty.
- High concurrency and real billing acceptance must be tested under a production-like PostgreSQL instance before R1.
- Security audit for picomatch is still a separate mandatory blocking gate; no suppression.

No local owner DB migration, main merge, Railway deploy or charge was performed by this slice.
