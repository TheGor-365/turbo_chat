# H3g — Context Intelligence Backend (10 Nov 2026)

Status: **implemented in Draft PR #2; test and local acceptance tracked separately**.
Branch: `feat/security-baseline-2026-11-03`. Never merge to `main`
or deploy Railway without separate owner approval.

## Goal

Relay Workspace: conversation → grounded next reply, summary, action items,
client brief, client proposal or content outline. No generic chat agent, no
automatic content publication and no unrestricted history transfer.

## Data path

`POST /rooms/:id/ai/reply` or `/ai/task` →
`RoomContextAccess` →
`ReplyContextBuilder` (PostgreSQL Room.messages only) →
`ContextReplyPromptV1` or `ConversationTaskV1` →
`XaiResponses` (grok-4.3, store:false, tools:[]) →
`ReplyOutputGuard` →
ephemeral preview JSON + source message IDs →
human edit → Apply → ordinary Send.

Approval to contact xAI is one explicit click per request.
A separate persistent, revocable per-room/member **sharing grant** is also
required. A single member cannot authorize peers' message content.

### Consent

- Migration: `db/migrate/20261110200000_create_ai_room_context_consents.rb`
- `AiRoomContextConsent`: one record per user and room; grant/revoke timestamps.
- Private direct messages and private groups only, with 2–10 current members.
- Each current member must opt in. Former members' messages are excluded.
- Public rooms, missing grants, revoked membership and absent migration fail closed.
- The Smart replies toggle is a **permission** to process the consenting
  author's historical messages in the room, not permission for automatic AI
  requests or chat sends. Clear notice must remain visible.

### Retrieval and token economy

- Retrieve latest 24 candidate text messages **only from this room** and only
  from current member authors; at most 9 excerpts in the provider request.
- Max 420 chars per message, max 2,400 chars total; chronological within
  selected scope. No attachment bytes, files, external messages or embeddings.
- Address/token heuristics exclude detected sensitive messages. The filter is
  conservative but not a complete DLP system.
- The backend also requires a usable incoming message, not just the user's own
  notes. Results carry actual `source_message_ids` for user verification.
- A task-specific, immutable system prompt gives the model a short algorithm.
  The user note is at most 700 chars/2,800 bytes.
- Reply generation max 384 output tokens; business tasks max 600–750.
  `reasoning.effort = none`, `store = false`, `tools = []`.
- The output guard blocks obvious unsupported URLs, money amounts, dates and
  detected personal identifiers. It does **not** guarantee factuality and can
  reject legitimate reformatting. Missing details must be labeled To confirm.

### Available workflows

- `POST /rooms/:id/ai/reply` body
  `{"reply":{"consent":"1","request_id":"<UUID>","hint":"optional note"}}`
- `POST /rooms/:id/ai/task` body
  `{"task":{"kind":"client_brief","consent":"1","request_id":"<UUID>","hint":"optional note"}}`
- Task IDs: `conversation_summary`, `action_items`, `client_brief`,
  `client_proposal`, `content_outline`.
- `GET /rooms/:id/ai/context-consent` returns only status counts, no content.
- `PATCH /rooms/:id/ai/context-consent` body
  `{"consent":{"enabled":"1"}}` or `{"consent":{"enabled":"0"}}`.
  Only logged-in room members can change **their own** grant.
- All endpoints require normal application CSRF/session authentication.
- No Message records, notifications, broadcasts, exports, tasks or background
  jobs are created by AI generation.

### Kill switches / deployment boundaries

All context features are disabled by default, and tests use mock transports.
They require development-only `XAI_DRAFT_GENERATION_ENABLED=1`,
a valid private `XAI_API_KEY`, and `XAI_CONTEXT_REPLIES_ENABLED=1`
to enable contextual replies. `XAI_CONTEXT_TASKS_ENABLED=1` is a separate
opt-in gate for the five business task endpoints. No production path was opened.

Existing `LocalBudgetLedger` limits apply: reserve $0.10 per call; cap $0.30
per user/day, $1 per user/month, $2 per installation/month. The request is
rate-limited, the room and grants are rechecked before external dispatch, and
unknown billing outcomes retain reservation. No automatic paid retries.

### Local schema warning — do not skip

The owner's checkout had a **deliberate modified `M db/schema.rb`**.
This stage introduces ONE migration but does **not commit or rewrite**
`db/schema.rb`. The local `compose.yaml` web command runs
`bin/rails db:prepare` on every start; that may apply the migration
and regenerate the local schema.

**Do not instruct the owner to run Docker / db:prepare just to accept this
checkpoint before preserving and reconciling their local schema diff.**
First inspect `git diff -- db/schema.rb`, and save a verified safe backup of
the actual schema file and PostgreSQL data. Do not reset, restore, discard,
overwrite the schema, or delete volumes. Only after verifying the preexisting
local changes should a controlled local migration be run.

### Deferred for subsequent milestones

- Owner visual acceptance and one real, explicitly approved paid request
  (no calls were triggered by tests).
- Longer-history relevance retrieval, full source-attribution UI,
  participant audit history, privacy policy/legal review, product analytics,
  token usage telemetry, grounded search and multi-document RAG.
- Production consent revocation semantics across multiple workers and
  granular sharing policies need a separate security review.
- Stable Conversation → Deliverable persistence/export and optional
  integration side effects require explicit new approvals.
