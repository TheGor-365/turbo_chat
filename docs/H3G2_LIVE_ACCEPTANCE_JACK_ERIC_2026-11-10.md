# H3g.2 — Jack / Eric live xAI acceptance (private, paid, opt-in)

Branch: `feat/security-baseline-2026-11-03`, Draft PR #2.
No changes to main or Railway. The owner operates TWO existing local
accounts in normal Chrome and Chrome incognito. No fake HTTP response stubs.

## Before any paid call

- Private PostgreSQL + Active Storage backup verified. AI consent migration
  `20261110200000` is UP. No use of `db:reset`, schema replacement,
  secrets in chat, or volume deletion.
- In **private local** `.env.local`, retain the existing `XAI_API_KEY`.
  If not already set, enable these exact flags, each ONCE:
  `XAI_DRAFT_GENERATION_ENABLED=1`,
  `XAI_CONTEXT_REPLIES_ENABLED=1`,
  `XAI_CONTEXT_TASKS_ENABLED=1`.
- Recreate only the web container after a flags change:
  `docker compose up -d --no-deps --force-recreate web`.
  This re-runs `db:prepare`, so confirm no pending migrations first.
- Run `bash bin/h3g_live_readiness.sh --read-only 1`. The output has no API
  key, chat text, emails or user IDs. Verify three feature flags and
  `consent_table_present=true`. For room 1 check `room_private=true`.
- The browser may already display six draft styles even when contextual AI
  is OFF. `ContextReplyGeneration.enabled? = false` MUST be resolved
  before expecting a Smart replies switch.
- Requests are billable. Grok only executes when the user clicks its button.
  Local caps: $0.10 reserved per request, $0.30/user/day,
  $1/user/month and $2/installation/month. Failed/unknown requests
  may retain reservations. No automatic retries or auto-send.

## Scenario A — permission gate, $0

1. Jack (normal or incognito): private DM with Eric, Room settings
   → Smart replies **ON**. Result: awaiting other participant (1/2).
2. Eric: Room settings → Smart replies **ON**.
   Result: both sides show ready (refresh Room settings if necessary).
3. Eric opens Edit draft with empty composer: **Suggest reply with Grok**
   becomes available. Do NOT click until Scenario B messages are posted.
4. One user revokes permission to test block; the other account must no
   longer be allowed to request context. Re-enable before Scenario C.
   Permission changes do not call the paid API.

## Scenario B — real, synthetic conversation, $0 to send

**Jack**, send:
> We need a Ruby on Rails JSON endpoint for product status. Use our
> existing PostgreSQL database. Filter by status and sort by created_at.
> The budget and deadline have NOT been agreed.

**Eric**, send:
> I understand the Rails endpoint, PostgreSQL, status filter, and
> created_at sort. I need to clarify accepted status values,
> authentication, and the response format before estimating.

**Jack**, send:
> Please recommend a next step. What details do you need from me?
> Do not propose a fixed price or delivery date yet.

Use synthetic details only; do not type passwords, payment details,
real client content, private IDs, addresses or access tokens.

## Scenario C — REAL paid contextual reply (Eric)

1. On Eric's account leave the composer blank.
   Open Edit draft → **Suggest reply with Grok** → click **once**.
2. Expected: proposed next answer drawn from the Rails/API conversation,
   asking for relevant missing facts; no invented dollar quote or deadline.
   A reference list of source message IDs and reported provider cost appear
   under Details. Nothing is sent to chat automatically.
3. Edit the proposed answer manually if needed → **Apply to message** →
   inspect the main composer → **Send** explicitly.
   Check that Jack receives the actual message via ActionCable and that
   sender/recipient displays match.

Report status text, a screenshot and `cost_usd` only; never copy secrets
or real private conversation.

## Scenario D — real contextual work products (Eric)

- Edit draft → Work with conversation → **Client brief** →
  Generate with Grok (one paid call).
- Expected output: objective, confirmed scope, unknown constraints, and
  To confirm for budget, deadlines and status details. Sources should be
  real [M...] IDs. Preview is NOT auto-posted.
- Optionally repeat with `action_items` or `conversation_summary`
  only after reviewing per-request cost and current budget.
- Each generation is a new billable click. Existing source content
  comes from the same private room, only after both consents.

## Scenario E — 6 draft styles (separate paid calls)

- Compose a deliberately flawed TEST sentence under Eric:
  `I has finish the rails api and can delivers tomorrow.`
- Edit draft → Polish / Clarity → Improve with Grok (one paid call).
  Check edits first, then Apply and optionally Undo.
- Translate Preserving Tone requires explicit target language.
  One translation request is another paid call; never infer consent
  from the previous request.

## Failure diagnosis

- No Smart replies: check `XAI_CONTEXT_REPLIES_ENABLED` in running
  Rails readiness output and `room_private=true`; in a public room
  history-based AI is forbidden.
- Consent pending: both *actual* logged-in room members must enable.
- HTTP 422: missing consent or unsafe/invalid context.
- HTTP 429: local rate or cost budget reached. Stop, do not retry blindly.
- HTTP 503: provider or environment disabled/error. Stop; inspect
  sanitized server status, not raw API key/body.
- Model access and billing: official xAI Responses API returns
  `usage.cost_in_usd_ticks`; the app records settled cost in the local
  ledger. Do not assert success from the UI button alone.

## Acceptance

Human-reviewed results: correct private-room access, correct speaker
perspective, grounded missing information, one paid call per click,
no automatic chat send, real actual provider cost, actual delivery to
the opposite browser, and permission revocation. Remaining issues
become a new H3g.2 checkpoint; production deployment is separately gated.
