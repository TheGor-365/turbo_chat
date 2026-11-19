# H3a — server-side own-draft preparation (2026-11-10)

**Status:** code-only *preflight*, not a connected API, consent ledger, payment approval or production use.

Owner approved proceeding toward H3 real AI, but the OpenAI Platform key setup did not complete: the user declined the connector confirmation. No API key or billable request exists. Do not retry that setup flow or assume a connected ChatGPT subscription is Platform credit.

This slice adds `AiWorkspace::OwnDraftPreflight`, a narrow Rails service that only prepares the logged-in actor's own unsent text under live room membership, explicit per-attempt preview flag, immutable `beautify` preset, and existing 5,000 characters / 20 KB validation. The flag is **not legally meaningful provider consent** and must never be used to authorize transmission. No network, controller route, persistence, AI-output, browser secret or paid call was added.

The existing `AiWorkspace::Gateway` stays fail-closed. AI and AUTO must stay OFF in UI.

Before enabling an outbound call, independently verify provider/model/legal region, current terms/retention, actual Platform account billing and project key handling, and agree concrete spend limits per request/day/month; implement enforceable server-authoritative consent and budget gate with tests, including revocation immediately before dispatch. If durable tables are needed, backup and approve any additive migrations separately. Avoid sending any real user/chats/attachments in the first e2e call; use synthetic draft only. A browser checkbox alone is not enough.

Review scope: no changes to routes, schema, messages, attachments, Redis, storage, main, Railway, user-local Docker volumes.
