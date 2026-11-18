# Automation modes V2 — implementation contract

Date: 2026-11-18. Status: foundational implementation; do not call it a working auto-reply product.

## Independent axes

1. Reply mode **off / review / full_auto** (one member in one private room).
   - \`review\`: future event-driven suggestion requiring a human Apply, then a separate Send.
   - \`full_auto\`: future explicit, branded automated Send for low-risk allowed intents, after simulations and all runtime gates.
   - Existing manual Beautify and contextual Answer remain available as their current opt-in flows. Saving policy changes neither flow.
2. Outcome mode **off / manual / after_messages / daily** with document kind.
   - Currently an explicit offline preview of **conversation_summary** or **client_brief** exists, reusing H4 extractive builders, with unanimous live consent.
   - \`after_messages\` and \`daily\` store requested settings only; there is no scheduler/worker.
   - \`action_items\` and \`open_questions\` are reserved output choices, not currently supported by the offline preview endpoint.
   - H5 already supports owner-scoped saved versions and MD/TXT export with current ACL; never duplicate it.

## API and hard gates

- GET/PATCH/DELETE \`/rooms/:room_id/ai/automation-policy\`: account- and room-scoped configuration with revision conflict protection.
- POST \`/rooms/:room_id/ai/automation/summary-preview\`: authenticated, private, unanimous current consent, bounded text-only source selection, source links, **no external provider**, no saved records, no Send. Supports \`conversation_summary\` and \`client_brief\` only.
- All policy snapshots disclose \`configuration_only: true\`, \`unattended_send_active: false\`, \`reply_generation_active: false\` and \`scheduled_summaries_active: false\`. These values are not flags the user can mutate.
- No database schema export in git; local \`db/schema.rb\` was modified prior to this slice.

## Required future runtime work

1. S2 effective settings resolution, S3 generation orchestrator, enforce current goal version and source fingerprints.
2. S6 production provider and PostgreSQL budget/usage ledger.
3. Worker + durable \`AiAutomationRun\` and uniqueness \`{room,user,incoming_message_version,policy_version}\`, cancellation, delayed replay, consent recheck.
4. For Apply mode: save a proposed candidate, human acknowledgement, separate human Send.
5. For full auto: explicit opt-in activation, verified readiness, dry-run 3–5 scenarios, allowed-intent scripts, per-user limits/office hours, bot labels, kill switch, anti-loop and final checks.
6. For outcomes: trigger from new messages and daily schedule, dedupe, new types of summary, source citations, H5 drafts and versioned MD/TXT now, PDF/DOCX only after tested exports.

No auto-merge, Railway deploy, live/paid AI, or local owner database migration was performed by this change.
