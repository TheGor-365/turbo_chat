# ADR — Relay Workspace Content Intelligence Engine: Gate 2B.0 (2026-11-09)

## Status
Offline engineering contract, not provider rollout. Builds on ADR 2026-11-08_AI_WORKSPACE_GATE2A. No AI provider, billing, data retention approval, room consent, migration, external request or generated text. Existing Gate 2A screen and tests remain unchanged.

## Input and trust boundary
Future structured input: actor, room, source (own_draft / selected_messages / approved_context), source_ids, operation, validated preset and optional target_locale. Authenticated server principal, live room membership and scoped message lookup are authoritative; client parameters never authorize room access. Never accept user-provided raw system instructions.

ContentPipeline#prepare produces only ephemeral local rows and metadata. It does not invoke Gateway, persist, broadcast, enqueue, send messages, or read room history automatically. Own draft max 5,000 characters, and explicit selected messages only through the existing AiWorkspace::Scope. Future approved_context is denied until consent is implemented.

## Context policy
Default manual: 1–8 distinct decimal IDs from the authorized room, text only, chronological ordering, 750 Unicode characters per selected message. These restrictions come from the existing Gate 2A Scope and are not duplicated as a second message store. Smart and agent modes are denied with ConsentRequired. No attachment data, member list, automatic history, RAG, mailbox access or invisible background processing. Token budget is a separate future limit, not equivalent to preview character limits.

Future smart mode needs explicit opt-in, participant permission model, exact source preview and revocation. Before any provider work, recheck rights at request time and immediately before the outbound job call.

## PresetDefinition v1
Immutable code-owned configuration, strict schema_version=1 and version=1. Exact allowed keys: schema_version, id, version, operation, label, locale, intent, audience, tone, style, constraints, context, output. Reject unknown keys, unknown enums, arbitrary prompts and unsafe version changes. Supported operation vocabulary: beautify, summarize, translate, suggest_reply. Facts preserved; fabricated prices/deadlines prohibited; author approval required. Context policy manual, max_messages at most 8; narrower preset limits are enforced before the canonical Scope lookup. Output plain_text, one variant. Frozen snapshot prevents post-validation changes. This is a schema contract, not yet a six-preset catalog or persisted records; bundled presets follow in 2B.1.

## Pre/post processing
Implemented conservative deterministic Text preprocessor: normalize line endings and Unicode NFC, reject empty/invalid/control/oversized input (5,000 characters or 20,000 bytes), preserve code, Markdown, URLs, quotes and meaningful whitespace. Provide metadata-only possible_email and possible_secret warning flags. No claim of complete redaction or secret detection; matched values are not returned as warnings or logged.

Future preprocessors may add language detection, segmentation and source-supported fact suggestions. Future postprocessors may add safe output escaping, format/length checks, verified source/link warnings, variants and reviewable diffs. Model output stays untrusted and never auto-sends.

## Gateway, output and errors
The existing AiWorkspace::Gateway remains fail-closed (configured? false, ProviderUnavailable), without a transport, provider SDK, credentials or paid calls. Prepared output contains source, operation, immutable preset snapshot, rows with local source ID/text/warning flags, and character count. It is not an AI response.

Sanitized error taxonomy: Unauthorized, InvalidSelection, InvalidPreset, ConsentRequired, BudgetExceeded, ProviderUnavailable. For future HTTP endpoints: 403 unauthorized; 422 invalid selection/preset/consent/budget; 503 provider unavailable. No new endpoint in 2B.0, so Gate 2A headers, controls and HTTP behavior are unchanged. Never echo raw prompts, secrets, foreign messages or internal traces in errors.

## Next approval gates
2B.1 bundled 5–6 immutable presets + selector on the existing AI Workspace, with Generate disabled; 2B.2 composer and non-sending draft preview/apply UI; 2B.3 durable consent/retention ADR and separately approved additive migration. Inspect the intentionally modified local db/schema.rb, migration status and safe backup before any such migration. Provider choice/eligibility/retention/budget and real inference require a separate owner decision.

## Verification / non-goals
Test strict versions/enums/immutability, Unicode and malformed inputs, room and cross-room scope, revocation, consent lockout and Gateway refusal. Verify Rails/Redis/Chrome/Security/Docker checks against the exact resulting commit. Do not change main, Railway, Gmail, Google Drive, local volumes, storage, seeds or owner databases.
