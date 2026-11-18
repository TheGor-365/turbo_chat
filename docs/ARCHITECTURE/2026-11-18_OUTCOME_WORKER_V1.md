# S7-C Offline outcome worker — first bounded vertical slice

Date: 2026-11-18. Status: implemented in feature branch, subject to exact-SHA CI.

The queue stores **one work item per AiAutomationRun** with states
`queued → leased → completed|blocked`, capped retries and row-level
`FOR UPDATE SKIP LOCKED` claiming. Recovery of an expired lease is safe
because document creation and item completion commit in the **same** DB
transaction. No raw chat text or generated body is stored in the queue.

`AiWorkspace::AutomationOutcomeWorker` can explicitly enqueue and
process a pre-recorded `conversation_outcome` run. It checks live room
membership, unanimous **manual context** grants, additional explicit
**background processing** grants from all current participants, the user's
separate **scheduled outcome** grant, policy revision and unchanged cited
context. It creates an owner-scoped H5 `AiDeliverable` draft with one immutable
revision from the existing H4 deterministic builders. It NEVER calls the AI
provider, sends chat messages, marks source statements approved or charges
the ledger. A missing consent or stale message blocks the work item.

Only `conversation_summary` and `client_brief` have implemented offline
builders. `action_items` and `open_questions` remain planned, not faked.
No event producer/scheduler has been connected; the queue is invoked only
by an explicit service call. No production worker process was launched.

Future S7-C: safe event producer for N-message thresholds + daily UTC windows;
run status, user notifications and history; longer-context selections; richer
document formats via H5; single real worker process with graceful stop and
operational metrics.

Future S7-A/B: candidate generator, human Apply and separately explicit Send;
production provider/budget/consent and safe unattended auto Send after dry-run.
DO NOT connect unattended chat Send to this offline queue without a new
security and authorization design.

No main merge, Railway deployment, local owner migration or paid request.
