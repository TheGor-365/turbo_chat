# S7-C opt-in outcome event producer (18.11.2026)

- A finite polling producer discovers configured after-N and daily policies, with live unanimous manual AND background permissions and the owner's scheduled-document permission. It never acts on Message#create, costs nothing, does not Send messages, and does not mark generated documents approved.
- Manual execution entrypoint: `bin/rails ai:outcomes:run`; it **aborts by default** unless `AI_OFFLINE_OUTCOME_SCHEDULER_ENABLED=1`. No Cron/Railway scheduler is configured in this commit.
- After N: the API creates the durable baseline cursor at policy save and advances it only after successful idempotent enqueue. Previously sent messages are not backfilled. The H4/H5 document quotes at most nine safe citations from that specific message-ID window, not the full transcript.
- Daily: on a scan, consider only the PREVIOUS UTC date if the policy predates that day's end and at least one eligible message exists. Source retrieval is strictly limited to that date, with idempotent queue keys.
- The run stores its exact optional source bounds; original, window-scoped source hash and IDs are revalidated before H5 creation. A revoked permission/edit blocks the item rather than silently shifting its sources.
- Next: notification/UI for created drafts, catch-up rules, durable schedule deployment, rate/concurrency benchmarks, Apply proposals. Production AI and unattended Send remain disabled. Security release gate must still resolve vulnerable picomatch in yarn.lock.
