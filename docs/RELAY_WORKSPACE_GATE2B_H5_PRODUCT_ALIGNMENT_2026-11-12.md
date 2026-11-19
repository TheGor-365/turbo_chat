# Relay Workspace — Gate 2B → H5 product and engineering contract
Date: 2026-11-12
Status: proposed design; **no migration, persistence, production release or approved publishing**.

## Product north star (from owner concept)

Turbo Chat is an AI-first working messenger, not a replacement for Telegram/Slack/ChatGPT. The commercial product is **Relay Workspace: Conversation → Beautifier + Context → Workflow → Deliverable**. A reusable Content Intelligence Engine can later power a standalone Content Beautifier. Primary audience to validate: small digital agencies/content teams (2–10 participants); second audience: freelancers/small studios. Market need and pricing remain hypotheses, not measured demand.

**P0 user journey**: compose or select an authorized conversation → privacy-aware preprocessing → explicit business preset (scope, tone, audience, output contract) → constrained model gateway and metering → postprocessing/citations → version preview → optional human review/approval → separate export or Send. Default assistance should be automatic *inside user-initiated boundaries*, not autonomous external billing. The Signal Deck interface stays Rails 8 + Hotwire/Stimulus; no Vue rewrite or new service for this milestone.

## Reconciliation with current implementation

| Concept | Current verified implementation | Missing / next gate |
|---|---|---|
| Personal Writing Copilot (P0) | Compose AI, draft styles, preview, separate Apply and Send | reusable versioned brand/personal voice and A/B outputs |
| Contextual Conversation Copilot (P0) | room member consent, bounded/DLP-scanned context, explicit tasks, selected sources, author hint | configurable Manual vs Smart policy without increasing available data |
| Content Intelligence Engine | Preprocessors::Text, ReplyContextBuilder, code-owned ConversationTaskV1, xAI gateway, budget ledger, evidence/semantic gates | cohesive **versioned preset configuration** and reproducibility metadata |
| Conversation → Deliverable (P0) | real xAI Client Brief tested, linked messages, H4 typed Manual Review, session-only recovery | **H5 draft/versions/approval/export**; no durable revision record |
| Conversation Memory & Research (P1) | references to bounded permitted messages, not a factual knowledge base | durable approved decisions/task provenance, search scoped to current memberships |
| Automation Studio (P2) | not released | no unattended Send, external integrations or agents yet |
| Reliability for paid customers | Docker/Redis realtime acceptance, source/ACL tests | release-blocking stable H7 and end-to-end task/consent tests |

### Sequencing — protect product focus
1. **Close H4 quality gate**: deterministic recovery test green, source/citation review, no automatic Apply/Send or double-charge, H7 realtime regression tracked separately.
2. **Gate 2B architecture and versioned agency preset**: explicit inputs (task, format, audience, brand rules, language, forbidden claims, source policy), immutable version identifier, shared engine contract and tests. Do not expose seven bots.
3. **H5 deliverable lifecycle**: immutable revisions, reviewer decisions, source snapshots/references, explicit publication approval, separate export/Send. This is the minimal commercial deliverable loop.
4. **Pilot measurement**: first useful document, review edits, export/approved deliverables, repeat use and cost per *accepted* output. Only then prioritize full-content packs, more tools or standalone Vue interface.

## H5 storage proposal (pending explicit database approval)

Use server-side PostgreSQL records after owner approval of migration/backup/retention:

- `ai_deliverables`: `id, room_id, owner_id, kind, preset_key, preset_version, title, state, current_revision_id, created_at, updated_at`. State machine: `draft → in_review → approved → archived`; **reviewed != approved**. Never `sent` as an implicit state change.
- `ai_deliverable_revisions`: `id, deliverable_id, revision_number, author_id, body_markdown, body_sha256, provider_model?, reported_cost_ticks?, created_at`. Append-only after creation; unique `(deliverable_id, revision_number)`. No secrets, raw prompt logs or unselected room histories.
- `ai_deliverable_claims`: `revision_id, position, section, claim_text, status` with `inferred|unknown|needs_confirmation|confirmed`; every confirmation stores a real human review and means designation only, not verified truth.
- `ai_deliverable_sources`: `revision_id, claim_position, message_id` with room-bound foreign keys/application validation; **never** serve source text without live room membership and current shared-AI consent. Permission revocation means no source disclosure or revision containing its text until re-authorization.
- `ai_deliverable_reviews`: `revision_id, reviewer_id, decision, reviewed_at`; reviewer and approval are separate actor actions; keep review history and immutable authorship.
- `ai_deliverable_exports` (only if needed after pilot): format, actor, at, revision hash, delivery destination and outcome; **export** never means **Send**. No autonomous outbound actions.

**Retention proposal, not yet adopted**: no background model calls; no persistence by default unless user explicitly saves a deliverable. The owner selects a duration and deletion policy before schema deployment. Restrict downloads/export and document retrieval by fresh ACL/consent; do not treat historical approvals as perpetual authorization. GDPR-like privacy work and provider retention terms are separate launch gates.

## Security, UX and release gates

- Reuse Signal Deck, icon affordances, accessible labels and styled pickers. One primary surface: **AI Workspace**, not seven bot pages.
- New document is always a draft; model citations are pointers, not truth or client agreement; missing/unverified scope and price remain to-confirm.
- Confirm actor, active room members, all required consents and allowed source IDs at *every* retrieve, review, export and send endpoint. No stale signed link should bypass revocation.
- Enforce CSRF, XSS escaping, per-room isolation, idempotent payment requests, bounded content, metering and no leaked private content in errors/logs.
- Post-deployment acceptance must include two users, room removal, revoked consent, contradictory agreements, malicious citations, page reload and two-browser Redis realtime.
- No schema modification in this step: local `db/schema.rb` has user changes and **must not** be overwritten. No production Rails migrations, Railway change or merge to `main` until separately authorized.

## Explicit owner decisions needed before H5 migration

1. Who can create, review, approve and export a deliverable in a shared room: author-only, invited reviewers or room admins?
2. Should private content be durably stored by default or only after pressing **Save draft**? Recommended: explicit Save.
3. Data retention/deletion and whether removal from room makes a stored revision temporarily inaccessible or deletes it. Recommended: deny access immediately; decide deletion separately.

## First acceptance KPI

One team of two users can produce an evidence-linked Client Brief, correct it, save **v1**, revise to **v2**, compare, explicitly approve, export and retrieve the right version after a reload — without a duplicate xAI call, leaked revoked context or unintended chat Send.

## Gate 2B specification: reusable Content Intelligence contract (proposed, not active)

### Service boundaries

- `AiWorkspace::Preprocessors::Text` **exists** and normalizes bounded strings with email/token warnings. Do not promote it to full DLP or promise extraction of facts it does not perform.
- `AiWorkspace::ReplyContextBuilder` **exists** and retrieves at most nine bounded, currently permitted message excerpts. It is not RAG or full-history analysis.
- `AiWorkspace::ConversationTaskV1` **exists** as a code-owned task prompt registry. It currently defines five task kinds and max output token budgets, but it is **not** a reusable persisted agency/brand preset engine.
- `AiWorkspace::ContextTaskGeneration` and `AiWorkspace::Providers::XaiResponses` **exist** as the controlled model gateway; consent is checked again before provider invocation, and `LocalBudgetLedger` meters *development-only* spending. Do not reuse this ledger for multi-host production.
- `AiWorkspace::SemanticDeliverableGateV1` **exists** to validate structural sections/citations; it does not prove factual entailment or commercial agreement.
- **Proposed Gate 2B interfaces**, implemented incrementally as separate code-owned services, not new network services: `BusinessPresetRegistryV1.fetch!(key:, version:)` and `ContentTransformationV1.plan!(input:, preset:, context_mode:, scope:)`. A plan is inert; execution passes through existing gateway/ACL/ledger and never contains an automatic Send instruction.

### Proposed immutable preset configuration

Each published preset is versioned and immutable. Fields: `key`, `version`, `task_kind`, `audience`, `locale`, `tone`, `output_format`, `required_sections`, `source_policy`, `prohibited_claims`, `max_output_tokens`, `revision_policy`. The system owns instructions and section schemas. User-provided brand examples are bounded **data**, never appended as trusted system-level instructions.

Initial agency examples, **not yet implemented**:

1. `agency/client_brief@1` → `client_brief`, structured H4 sections, citations mandatory for factual claims, unknown timing/price to-confirm.
2. `agency/client_proposal@1` → `client_proposal`, excludes invented discounts, prices, commitments, claims of agreement, unsupported KPIs.
3. `agency/client_summary@1` → `conversation_summary`, explicit distinction between confirmed decisions, suggestions and unresolved questions.

Brand Voice is a higher-level rule profile attached to a versioned preset, not a seventh bot. Never ship a user-editable raw system prompt as the first preset interface.

### Context permissions and mode semantics

- `manual`: only actor-selected source IDs, strict bound and fresh membership check. No implicit transcript access.
- `smart`: deterministic bounded relevant message selection **after** all active participants opt in; source IDs are visible before a paid request. No scraping other rooms, attachments or departed users.
- `agent`: reserved for later Gate 3/P2; no autonomous external calls or sends. Requires distinct operation-level authorization and idempotency keys.
- On room removal or consent revocation, source data and any stored deliverable containing it must become immediately inaccessible until reauthorized. This applies independently of whether a provider request has already been paid for.

### API / method contracts for implementation

Existing client endpoints remain authoritative. These are **proposed future additions**, not currently active routes:

| Operation | Proposed contract | Safety invariant |
|---|---|---|
| List presets | `GET /ai/presets?task_kind=client_brief` → immutable key/version and display metadata only | no prompts, credentials, or room transcript |
| Preview transformation | `POST /rooms/:id/ai/plan` with `preset_key, preset_version, context_mode, selected_source_ids` | fresh ACL and consent; no provider call or charge |
| Execute transformation | Existing authenticated contextual-task endpoint extended with a **versioned preset reference** | explicit paid approval, budget reserve, fresh sources, idempotent request ID |
| Create draft revision | Proposed `POST /rooms/:id/ai/deliverables` with validated content and expected source scope | user explicitly presses Save draft, no implicit publishing |
| Review revision | Proposed `POST /rooms/:id/ai/deliverables/:id/reviews` with revision hash and per-claim decisions | active membership, approval separate, stale revision rejected |
| Export approved output | Proposed dedicated action with format and exact revision ID | explicit authorization and current ACL, auditable, no implicit chat Send |

No API route in this table is authorized for production implementation merely because this document describes it.

### Gate 2B/H5 acceptance

- Frozen preset v1 produces identical task schema under the same bounded input; changing configuration creates v2 and does not silently modify prior outputs.
- Source selection cannot exceed existing limits, cite other rooms or ignore revoked consent. Token/cost limits remain downstream of the authorization step.
- Draft, preview, reviewed, approved, exported and sent are distinct states/actions; version comparisons never silently approve changes.
- English/Russian content and realistic client dialogue with unknown deadlines/prices are tested alongside malicious prompt injection, forged citations, and blank context.

## H5 first implementation slice (owner approved, 2026-11-12)

The owner approved explicit Save draft, current-permission read denial and separate document deletion. The product must remain usable for **ordinary personal or household conversations**: AI and business artifacts are optional; no routine chat message requires item-by-item review, Save, approval or provider billing.

Implemented in Draft PR #2:
- Additive PostgreSQL migration `20261112130000_create_ai_deliverables_and_revisions.rb` creates private draft metadata and append-only revision rows. It is **not run locally or in Railway** by the assistant. GitHub-tracked `db/schema.rb` is deliberately untouched to avoid overwriting the owner's modified local schema; the owner must review, back up and apply migrations safely as a separate step.
- `AiDeliverable` and `AiDeliverableRevision` models; only an explicit **Save draft** from H4 writes v1. Revisions append v2/v3, older text stays unchanged, stale version updates reject.
- A room-scoped, owner-only controller rechecks unanimous active private-room consent and source IDs on creation, update and read. No cross-room ownership or revoked-source reads. No background model request or chat send.
- A minimal Signal Deck saved-work screen navigates versions and allows an optional further revision. The H4 Save action submits the **current edited textarea** via a form-linked submit button; it must not save a stale hidden copy.
- First milestone deliberately excludes review approval, team review, exports, deletion endpoints, new standalone UI and production use. These will follow independent security and product acceptance. The database migration is owner-approved conceptually, but must not be applied to production without backup and deployment plan.
- Tests target explicit save, no message writes, immutable versions, stale conflict, forged citation, changed consent, owner-only retrieval and optional UI affordance. The full Rails CI, Docker smoke and security audit must pass on the latest exact SHA before local migration instructions.

### H5 usability/security follow-up

- `Saved documents` is now a discoverable Signal Deck tile from the room's AI Workspace, with a private actor-owned index and simple empty state. No ordinary chat message is persisted as an AI deliverable.
- Explicit deletion is distinct from Save and Send. It requires an owner-only DELETE request with literal typed confirmation `DELETE`; it removes the entire document and its immutable revision rows, not the room conversation. Future retention/audit policy must be agreed before production.
- A saved document is denied if **any** of its historical citations belongs to an author no longer in the room. Source links are produced only for the selected version, enforcing the nine-source-per-version limit even when many versions exist.
- H5 first slice does not yet offer team approval, client sign-off, collaboration, export, version diff UI or a complete evidence-history audit trail; these remain separate release milestones, not claims of a finished commercial workflow.
