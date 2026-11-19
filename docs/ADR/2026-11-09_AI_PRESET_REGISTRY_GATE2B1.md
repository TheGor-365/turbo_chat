# ADR — Gate 2B.1: bundled, validated offline presets (2026-11-09)

## Status and dependencies
Implements the next increment after `2026-11-09_AI_CONTENT_ENGINE_CONTRACT.md` / Gate 2B.0. No external AI calls, message sends, new DB tables, persistence of presets/outputs, provider credentials or financial costs. Gate 2A selected-message review remains compatible for older POST payloads with no preset_id.

## Six versioned presets
Local immutable YAML at `config/ai_workspace/presets.yml`:
1. `polish_clarity` — beautify, neutral/balanced.
2. `professional_client_reply` — suggest_reply, client/professional/concise.
3. `friendly` — beautify, friendly/balanced.
4. `concise` — beautify, neutral/concise.
5. `translate_preserving_tone` — translate, neutral/balanced.
6. `technical_summary` — summarize, teammate/technical/concise.

All are `schema_version:1`, `version:1`; manual context only, up to 8 selected messages, facts preserved, prices/deadlines never invented, explicit author approval required, plain text single future variant. The names indicate intended future behavior, not current AI processing quality.

## Trust, schema, and UI
`AiWorkspace::PresetRegistry` reads only the bundled code-owned YAML under 20 KB through Psych safe_load (no aliases, custom classes/symbols). Exactly six unique approved IDs and all `PresetDefinition` enums/keys must validate; immutable copies prevent runtime mutation. Reject unknown/user-injected keys, version changes, invalid rules, duplicate IDs and unsafe YAML.

The existing room AI form keeps the task selector and manual individual-message checkboxes. A compact preset selector filters candidates per operation via Stimulus as a convenience; Rails independently checks the same compatibility, current membership, exact room ID selection, per-preset message cap and review permissions. An optional preset_id in POST preserves earlier Gate 2A API compatibility. New offline preview displays preset version/constraints and local character count/warning indicators without revealing warning matches. The actual source preview remains HTML escaped and bounded by the canonical Scope (1–8 IDs, 750 chars per message). A disabled `Generate unavailable` button states that real inference is not configured.

`Scope::OPERATIONS` now additionally recognizes `beautify`; no new network route or provider adapter has been added. Existing Gateway stays fail-closed. No automation may send drafted/derived content to a conversation.

## Verification and next gate
Expected exact-SHA Rails/Redis/Cable/Chrome, Docker smoke, and Security audit PASS. Server and Chrome tests cover six profiles, invalid YAML/schema/extra keys, wrong preset-operation pair, cross-room and revoked membership, selected-only preview and disabled generation. No local db/schema.rb change, migration, Railway, Drive or main merge.

After CI, owner uses the safe local fast-forward and Compose rebuild; one screenshot of new preset selection/preview satisfies this UI slice. Then Gate 2B.2 adds a composer-adjacent icon and non-sending draft-preservation flow. Consent data model and real provider stay separately approval-gated.
