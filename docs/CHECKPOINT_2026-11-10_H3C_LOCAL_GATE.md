# H3c — local-only manual Grok generation gate

Status: implementation under QA; NOT production-ready, not a claim of successful real xAI inference.

Owner reports their separate xAI API key, restricted permissions and auto-top-up settings are done. These settings are owner-reported, not directly API-verified. Never paste the secret into chat/Git, logs or screenshots.

H3c adds a development-only request endpoint gated behind both XAI_DRAFT_GENERATION_ENABLED=1 and a privately installed XAI_API_KEY, and a conservative single-host ledger in storage/ai_h3_local_budget.json. Defaults OFF. Request requires current Devise identity, live room membership, explicit consent on every call, the author's own non-sensitive draft and the immutable polish_clarity preset. There is no history or attachment access. No saved prompts or outputs, no automatic sending.

Budget: $0.10 reserved per call (includes a potential $0.05 provider guideline fee), max $0.30 per user/day, $1 per user/month, $2 across this local installation/month. Locks via flock, file synced before network dispatch. On HTTP error/timeout/crash, reserve remains charged until an explicit audited reconciliation; on success the measured provider cost is settled. Local accounting does NOT bound other applications on the same xAI account, and no app-level system can guarantee what a remote provider charges in all exceptional situations. Ensure auto-top-up OFF and monitor xAI Console.

This file ledger is strictly for single-host Linux Mint development with /app/storage bind-mounted. Do NOT deploy to Railway, multi-container hosts, ephemeral storage or production. A durable PostgreSQL budget/idempotency schema, participant-consent policy, revocation concurrency protections, billing reconciliation and audited key management are required before public rollout. Migration needs a separate owner-approved backup and DDL change, preserving db/schema.rb and existing data.

UI must say sending text to xAI; no implicit agreement, no automatic message submission. Generate returns a suggestion only to the requesting browser; Apply/Undo remain separate, then Send is a distinct manual action. No input/output payloads logged by application code.

Local setup only after CI PASS: securely write XAI_API_KEY and XAI_DRAFT_GENERATION_ENABLED=1 in ignored .env.local (not .env committed). Compose reads this optional env_file into web. Never echo key with docker compose config or put it into terminal command history; do not copy it to other connectors. First live test with synthetic text, no client/private content.

Documentation: https://docs.x.ai/developers/rest-api-reference/inference/responses, https://docs.x.ai/developers/cost-tracking, https://docs.x.ai/developers/pricing.
