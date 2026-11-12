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
