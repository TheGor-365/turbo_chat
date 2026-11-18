# H3b — xAI Grok adapter, locked behind existing Gateway (2026-11-10)

Status: adapter + network-free contract tests; not a live integration or authorized outbound path.

Owner created a separate xAI Console API key named `TurboChat-Dev-Grok` (masked key visible on screenshot). **Never copy/store its raw value in a PR, issue, AI chat, Google Drive, browser localStorage or app logs.** Owner's key may need local secret installation; its exact model/endpoint restrictions and auto top-up status have not been verified by the assistant. xAI balance observed $8.64 on an earlier screenshot; billing credit is not a hard monthly cap.

Official documentation checked 2026-11-10:
- https://docs.x.ai/developers/rest-api-reference/inference/responses — POST /v1/responses
- https://docs.x.ai/developers/model-capabilities/text/generate-text — `store:false` disables recoverable response storage
- https://docs.x.ai/developers/models/grok-4.3 — $1.25 / 1M input tokens, $2.50 / 1M output tokens for short context
- https://docs.x.ai/developers/cost-tracking — metered `usage.cost_in_usd_ticks`, 10^10 ticks per USD
- https://docs.x.ai/console/billing — auto top-up can be disabled

`AiWorkspace::Providers::XaiResponses` implements a fixed HTTPS-only, POST-only transport. Uses `grok-4.3`, `store:false`, `tools:[]`, maximum 800 output tokens, timeouts, bounded response size, no automatic retry, sanitized exceptions, explicit billed ticks, and validates only an `own_draft` + `beautify` ContentPipeline::Prepared with an unmodified bundled preset. Sensitive-looking email/token drafts are denied by conservative metadata rules; this is not complete DLP.

**The controller, the composer, and `AiWorkspace::Gateway` do NOT invoke this adapter.** Even if the process has `XAI_API_KEY`, no HTTP endpoint accesses it, so public AI/AUTO remain OFF. The adapter accepts a key only by constructor injection in code (mock value in tests), not from UI. This prevents accidentally starting billable traffic without an atomic consent and cost guard.

Before the first real call: owner verifies the key has only correct model + Responses/Chat endpoints, confirms auto top-up OFF or a hard billing cap, securely installs the secret in local-only environment, and approves a bounded server-side request/day/month metering gate, user disclosure and explicit per-request consent. Do not use owner DB migrations or reset volumes without separate DDL approval and backup. First test must use dummy content and be visibly opt-in; the server must enforce current membership and prevent stale drafts and duplicate requests.

No local working tree, server, Railway, main branch, database, media or Docker volumes changed by this GitHub commit.
