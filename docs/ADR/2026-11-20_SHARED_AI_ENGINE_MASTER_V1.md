# Turbo Chat V2 — Shared AI Context, Script and Generation Master V1

**Date:** 2026-11-20. **Status:** product/engineering master plan. Only the narrow AI Answer readiness UI fix is implemented in this PR. This ADR does **not** assert that contextual Beautify, full-history coverage, a script builder, GIF tooling or live production AI work.

## 1. Verified code baseline (feature branch `3194c85`)

- Quiet Depth unified composer switches **AI Answer** when the human editor is empty and **Beautify** when it contains text; human and AI candidates have independent Sends and aligned resize grips. Real browser CI at that SHA passed: Rails 652 tests / 10,710 assertions; Chrome 160 / 2,385; focused Chrome 46 / 662; security/image tests passed. Owner-local UI semantic acceptance remains separate.
- `AnswerGeneration` is a development-only one-shot xAI provider path with explicit paid click, room instruction revision, unanimous context consent, bounded source retrieval, PostgreSQL `PostgresUsageLedger`, post-invocation authorization and human-reviewed Send. It is gated by `XAI_ANSWER_GENERATION_ENABLED=1`, `TURBO_CHAT_AI_ANSWER_SYNTHETIC!=1`, local `XAI_API_KEY`, context/ledger tables and development mode.
- User's local report after container recreate: `ANSWER_LIVE=false`, `BEAUTIFY_LIVE=true`, `SYNTHETIC=false`. This is a local readiness/configuration failure; **not** evidence of an xAI request. Exact failed gate is unconfirmed until a safe boolean-only diagnostic is run.
- The AI Answer button's old handler navigates to room instructions if the room instruction goal is absent and to Smart Replies consent if not all members granted; otherwise, without the live generate URL, it shows provider-free source preview. New UI slice in this PR replaces surprise navigation with an explicit inline blocker and user-initiated setup/preview actions.
- `ManualDraftGeneration` + `DraftPromptV1` handle own draft only, with old `LocalBudgetLedger`, not authorized room history or room instruction. Default `polish_clarity` intentionally makes minimum changes and may return compliant input unchanged. User observed `жду материалы` → `Жду материалы.` costing $0.000363. This is not a strong contextual rewrite.
- Already exist: `GenerationOrchestrator`, `GenerationInputContract`, `WritingPreferenceResolver`, `AiRoomWritingPreference`, `AiAccountWritingPreference`, `ConversationExperienceV1`, `RoomAiInstructionRevision`, `RoomInstructionGoal`, `RoomContextAccess`, `AiRoomContextConsent`, `ReplyContextBuilder`, `SourceSelection`, `DraftProvenance`, presets, saved manual templates and H4/H5 document review/export. **Reuse**, do not make rival storage or goals.
- Retrieval currently scans at most **240 recent candidate messages**, chooses at most **9 excerpts / 2,400 characters**, and is **not** a full-history guarantee. `SourceSelection` allows explicit narrowing of one server-approved snapshot only. History consent is unanimous in private rooms; files have no implicit grant.
- The older `feat/security-baseline-2026-11-03` has separate S7 experimental infrastructure; do not wholesale merge divergent branches or enable Auto Send.

## 2. Product contract: one configuration, three levels of automation

**Shared source of truth:** a server-compiled `AiEffectiveGenerationPlan` (design name; **not an existing class**). Both manual Beautify and contextual Answer consume the same resolved settings, room purpose/instruction revision, eligible context policy, allowed sources, provider/format constraints, privacy permissions and versioned script. Only the **mode and author draft** differ.

- `beautify`: requires authored nonempty text; preserves facts, negations, links, names, technical strings and source. Contextual mode may use room conversation **only after** all necessary member consents and an explicit opt-in; an own-draft-only option must remain. Helpful editing may include structure, tone, punctuation, language, limited emoji and requested formatting. No fabricated prices, dates, commitments, quotes or media.
- `answer`: empty author draft; uses selected latest or historical incoming message(s), current room purpose and effective shared settings; generates an entirely new editable suggestion. Needs verified eligible sources, permission, valid revision and reserved budget.
- `auto_reply` / **AI Dialogue**: same plan with an additional versioned automation policy, playbook and durable worker; delayed, bounded, opt-in, dry-run first, idempotent, kill switch, no AI-to-AI loops; strictly later S7. No automatic sending is authorized by this ADR.

The user controls which paper plane sends. No generation click auto-publishes. The upper candidate remains editable and distinct from the human draft; queued lower-composer attachments never silently accompany upper Send.

## 3. Resolution and prompt/script pipeline

Compilation order:

1. **Immutable server safety gates:** membership/ACL, content limits, privacy, consent (context; media separately), provider privileges, cost ceilings, anti-injection; never switch these off from UI.
2. **Task and mode:** beautify/answer/auto, intended reader, goal/output type, optional per-message request.
3. **Effective preferences:** existing account defaults → current member's room preferences → per-message options. Distinguish **room-wide shared instruction revision** from **personal style**. Per-message overrides do not overwrite saved room/account settings. No accidental conflicting tone/language.
4. **Modifier catalog:** versioned allowlisted toggles with IDs, descriptions, precedence, applicability, incompatible pairs, safe defaults. An initial set: punctuation, spelling, readability, paragraphing, bullets, concise, formal, warm, technical terminology, translation, greeting, closing, ask-one-question, preserve commitments, limited emojis (off/low/medium), Markdown formatting, audience adaptation. Never promise that all toggles can be combined; show conflicts and effective values. No external GIF/media sending without a separate asset workflow.
5. **Script / playbook:** generate a human-readable preview of the *effective instructions* from settings, selected modifier IDs and source coverage; allow named save, revision, duplicate, manual edit and an explicitly paid **AI-assisted script proposal** for human review. Keep a diff against server defaults. Editing script affects lower-trust task preferences, **not** immutable system/authorization rules. Reuse existing saved templates/revisions where possible; introduce new model/migration only after storage audit.
6. **Context snapshot:** stable eligibility boundary; filters by dates, author, message IDs, topics and include/exclude. Default UI selection can be `all eligible` **only when consent is already valid**. It means *consider all eligible messages*, not send all raw bytes: short history direct, long history indexed/hierarchical retrieval and versioned summaries. Show `total/scanned/eligible/selected/included/excluded/truncated`, source IDs and why excluded. Never state full coverage until implemented.
7. **Compilation:** code-owned SYSTEM; untrusted room instructions, transcript excerpts, one-shot script and knowledge are DATA, not server authority. Deterministic JSON schema, provider model, token/cost estimate and source fingerprint. Show user a **Human-readable generation contract** (purpose, effective style/language/tone, modifiers, selected context, why a source is used, model/budget, script version, privacy).
8. **Provider + audit:** one explicit request ID, PG reservation, no automatic retries, returned text/usage/factual cost and warnings. Validate unsupported claims, mark stale output, persist provenance and compare factual claims with source IDs before Send. Do not store secrets in logs.

## 4. Prevent paying for nearly unchanged Beautify text

Do **not** impose an unconditional “change anything, even if correct” rule; forced changes can damage correct technical writing and inflate unsupported claims.

Instead:
- **Preflight:** cheap deterministic checks for obvious punctuation/casing and a "may already conform" indication; if user requests a semantic rewrite, use the selected `professional_client_reply` / expressive modifier rather than conservative `polish_clarity`. Do not call provider silently.
- **Output contract:** classify `changed`, `unchanged_compliant`, `blocked` or `needs_review`. For unchanged-compliant results, show explicit notice and honest cost, keep manual Send. Avoid paying for a second identical attempt without a changed configuration.
- **Quality:** compare normalized meaning, check negations, facts and instructions; test short `привет`, `жду материалы`, mixed RU/EN technical snippets, and conflicting client budget/acceptance. Emoji/GIF must be controlled by user settings and context (e.g., avoid unsolicited emoji in business threads).
- **Measurement:** semantic fidelity, effective-setting adherence, usefulness delta, unchanged rate, latency, provenance, cost per useful candidate; record model, script version, selected sources and output without creating private data telemetry.

## 5. UI composition / Quiet Depth

One **Generation Inspector** used by Answer and Beautify, anchored near the twin editors, without creating a second competing settings system:

- **Outcome:** “What I am asking AI to do” and effective room purpose.
- **Writing style:** shared profile/language/tone, per-message override badges, modifier toggles with human-readable effects.
- **Context:** authorized coverage summary, source preview, filters/include-exclude; explicit `own draft only` / `use permitted room context`. No hidden context escalation.
- **Compiled script:** visible expandable effective plan, save-as template, rename, manual edits, separate AI-assisted script suggestion/Apply/Undo; display revision, effective precedence and whether current candidate is stale.
- **Provider/economics:** model, privacy/retention note, max reserved amount, actual charge and single-click confirmation; separate manual Send.
- Existing top AI and bottom human editors remain pixel-aligned and independently resizable; regenerate only after a *material* configuration/script/context change and explicit charge confirmation. Reduced-motion, 320/360/390px, keyboard access.

## 6. Implementation slices and acceptance gates

| Gate | Work | Proof |
|---|---|---|
| **T0 (now)** | Diagnose `ANSWER_LIVE=false` with boolean-only local check. Replace surprise AI Workspace navigation on missing goal/consent/provider with inline blockers and explicit setup action. | Focused Chrome; no provider call; no unintended permissions |
| **T1** | Final shared effective settings inspector; render a compiled script / context / budget preview **without paid AI**. Reuse existing preferences/templates; no new DB yet. | Consistent Answer/Beautify settings and precedence; preview no spend |
| **T2** | One real Answer request from approved synthetic private chat; verify goal/consent, xAI response, Russian tone, provenance and PG bill, keep unsent. | Actual model output + `settled` ledger row; stop on `uncertain`; no invented scope/budget/deadline |
| **T3** | Rewire contextual Beautify to same `GenerationOrchestrator`, `PostgresUsageLedger` and source fingerprint; keep own-draft-only toggle. | Identical effective settings and consent; no cross-room leak; cost gate |
| **T4** | Modifier catalog, script builder, auto naming, manual and optional AI-assisted script edits; integrate saved templates. | Reproducible named version; 1 script → same deterministic compiled inputs |
| **T5** | Full eligible-history snapshot/coverage, scalable retrieval and per-author/date/source filters, optional file knowledge gate. | Truthful coverage; edited/deleted/revoked sources invalidate suggestions |
| **T6** | S7 AI Dialogue dry-run/policies/workers; S8 dialogue-to-documents and exports; only then Railway R0/R1 and API commercial pilot. | No unattended Send until independent release approval |

**Current S0–S10 status:** S0 backups/restores and core composer Chrome CI pass; evidence M33/M34 local persistence/revoke still not owner-confirmed. S1 UI composes, but owner-live Answer acceptance blocked. S2 versioned room goal, preferences and consent exist; effective shared inspector and script controls are incomplete. S3 typed orchestrator + Answer compiled path exist; Beautify still bypasses shared contextual mode. S6 PG ledger works for Answer in development; Beautify remains on LocalBudgetLedger. S4 translation partial. S5 knowledge not implemented. S7/S8 separate branch prototypes/docs exist; not ready for automatic sending or full dialogue analysis. S9/S10 release not approved. Do not merge `main` or deploy Railway as part of T0.

## 7. Immediate owner checks — no secrets, no costs

Local branch must remain `feat/s3-s6-ai-answer-gated-2026-11-20` at `3194c85` with `M db/schema.rb` preserved. With `.env.local` loaded by Compose, run a read-only Rails runner that prints only booleans:

```bash
docker compose exec -T web bin/rails runner '
puts "rails_development=#{Rails.env.development?}"
puts "answer_flag=#{ENV["XAI_ANSWER_GENERATION_ENABLED"] == "1"}"
puts "synthetic_flag=#{ENV["TURBO_CHAT_AI_ANSWER_SYNTHETIC"] == "1"}"
puts "api_key_format_ok=#{ENV["XAI_API_KEY"].to_s.start_with?("xai-")}"
puts "context_table=#{AiWorkspace::RoomContextAccess.available?}"
puts "ledger_table=#{AiUsageReservation.table_exists?}"
'
```

Do **not** send the key, environment contents, PII or private room messages. If the answer flag alone is false, correct its exact existing setting in private gitignored `.env.local`, recreate **only** dev `web`, re-evaluate. Check saved instruction revision and 2-person consent counts separately before clicking Answer. No model request until `ANSWER_LIVE=true` plus all-member consent, valid room goal and one owner confirmation; even when `store:false`, xAI default retention should not be interpreted as zero-retention.

**References:** current repo code at `3194c85`, owner screenshot/terminal 2026-11-20; `docs/ADR/2026-11-15_CONTEXT_INSTRUCTIONS_MEDIA_ROADMAP.md`, `docs/AI_BEAUTIFY_QUALITY_ACCEPTANCE_2026-11-15.md`, `docs/AI_SEMANTIC_EVALUATION_MATRIX_2026-11-15.md`. The constraints on privacy and paid AI remain unchanged.
