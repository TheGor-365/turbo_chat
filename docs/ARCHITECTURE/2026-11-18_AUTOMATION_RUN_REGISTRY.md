# AutomationRun metadata registry (S7.3 — first slice)

Date: 2026-11-18. Type: non-executable audit metadata, not a job queue.

An additive `ai_automation_runs` table stores room/member/policy identity, versioned event key, hashed source fingerprint, bounded source IDs, requested kind, and status `recorded|canceled`. No raw chat text, model response, credentials, generated document or provider cost is stored.

`AiWorkspace::AutomationRunRegistry` deliberately has no public controller route, no callback from Message, no ActiveJob and no provider dispatch. Capturing a metadata event is not generation, does not set a paid reservation, and cannot publish to a room. It checks live room membership and unanimous **manual** context grants as an additional protective condition. Those grants are not enough for future unattended processing: dedicated opt-in, durable worker, budget and live Send checks are still required.

Reply events use a source fingerprint and goal/policy revision for idempotence; outcome events use an explicit bounded window key and current source fingerprint. A reconfigured policy cancels obsolete recorded metadata inside the same room lock. Canceled rows remain as history.

Next: persistent usage ledger with atomic limits; genuine durable worker with opt-in and reauthorization; Apply-only proposal state with human-reviewed provenance; unattended auto-send last; summaries via existing H4/H5 once separate scheduled-processing authorization is built.

Release: do not apply to owner local database until current exact-SHA 4/4 CI, backup PG/media/schema and safe additive migrations. No main merge, Railway deploy or paid API call.
