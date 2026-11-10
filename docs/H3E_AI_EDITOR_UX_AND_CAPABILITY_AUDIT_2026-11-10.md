# Turbo Chat / Relay Workspace — H3e UX + functional capability audit
**Date:** 2026-11-10 | **Branch:** `feat/security-baseline-2026-11-03` | **PR:** #2 (DRAFT)
**Status:** H3e code submitted for exact-SHA CI; owner-local design acceptance and real post-change AI request still PENDING.

## Verified owner observation (before H3e)
The owner ran a real, manual xAI Grok 4.3 proofreading request in the Rails app and accepted the corrected result. Owner screenshot shows `I have received the document and will answer tomorrow.` both in working copy and unsent composer, the status `Applied to the message. Nothing sent`, and an Undo action. Chat message was not automatically posted. The earlier API call reported a $0.000208 cost in the UI; reconciliation against xAI Console's bill is not shown. The owner requests faster editing, less text, size-adaptive fields, clearly distinguished before/after, subtle motion, and functional audit.

## UX defects grounded in code
- Six always-visible style chips + repeat provider/budget/privacy paragraphs + per-request checkbox consumed much of 500px-wide editor. Only one of the six presets actually invoked Grok.
- `f.text_field :body` yielded a single-line composer; the working textarea was fixed to several rows, rather than the content.
- `Apply` left the big overlay open, and finding Undo meant another UI search. Original and suggestion looked too similar.
- A prior model success with unchanged text misleadingly said "Review and click Apply"; fixed separately in H3d before this UX slice.

## H3e implementation scope (code-level)
- Collapse auxiliary style options and detailed provider/budget information in native `<details>`; keep short **visible** disclosure next to the action: clicking sends **only this draft** to xAI, does not send a chat message. This click is a fresh explicit per-request approval; Rails still validates `consent == "1"`.
- Replace checkbox + separate CTA with one visible **Improve with Grok** button. This operation always invokes the fixed, approved Polish / Clarity preset, independent of other locally saved style preferences. Other styles **do not** claim to invoke the model.
- When model returns a changed draft, display a clear **Before** block and **Suggested** editable field. Preserve explicit Apply, never auto-post. After applying a model suggestion, close the panel; a short Undo remains accessible beside the composer. Undo restores original text without sending.
- Use bounded auto-growing textareas in draft editor and message composer; desktop Enter submits as the prior input did, Shift+Enter inserts a newline, and coarse/mobile pointers keep newline behavior.
- Add small reveal animation only when `prefers-reduced-motion: no-preference`. Bound panel height and scrolling to viewport. All generated/model texts rendered with `textContent` / `textarea.value`, not HTML.

## Capability matrix (verified code vs product concept)
| Function | State | Evidence/limits |
| --- | --- | --- |
| Rails messenger / direct+public+private rooms / memberships | Implemented, integration/system tests exist | `RoomsController`, `PrivateGroupsController`, room ACL; owner local screenshots |
| Chat messages, files/media, replies, reactions | Implemented with tests | `MessagesController`, attachment controllers, message action system specs |
| Redis/ActionCable realtime, inbox, activity/search, profiles, light/dark | Implemented with CI and owner screenshots | Signal Deck baseline and historical H2.6 acceptance |
| AI own-draft Polish / Clarity via Grok | **One real owner test successful** | `ManualDraftGeneration`, `XaiResponses`, owner screenshot; local development only |
| Manual review/Apply/Undo/Send separation | **One real owner test successful; H3e redesign pending local retest** | Stimulus `ai_draft_controller.js`; no automatic Send |
| Budget enforcement | Local development only | JSON/flock local ledger, request ID, daily/monthly caps; not cross-server/production billing guarantee |
| Six presets | Registry + UI implemented, **only Polish / Clarity live on Grok** | `config/ai_workspace/presets.yml`, `PresetRegistry`; other styles are saved preferences, not live generation |
| Selected chat context and preview | Offline, ACL-protected, no provider dispatch | `RoomAiWorkspacesController`, `ContextPolicy`, `Scope`, `ContentPipeline`; must not imply Smart Context |
| Smart automatic permitted context, memory with source citations | NOT implemented as provider features | manual-only context policy |
| Real translation, professional/friendly/concise/technical rewrite | NOT live with model yet | Presets are definitions only; call gate hard-codes polish |
| Personal/Brand Voice, custom business presets | NOT implemented | No owner-created preset editing/versioning features |
| Conversation → Deliverable, action extraction, export | NOT implemented | No production generation/approval/export flow |
| AI AUTO, agent/automation chains, autonomous sending | OFF / NOT implemented | intended safety gate |
| Multi-server production AI quotas, participant consent ledger | NOT implemented | current development-only file ledger, no additive migration |

## Delivery validation gates
- Full exact-SHA Rails + Redis/Cable + browser suites, Docker smoke, security audit **must pass** before recommending local pull.
- New 320–390px/mobile tests must assert no panel overflow, collapsed descriptions, dynamic textarea height; desktop tests must assert textarea Enter/Shift+Enter behavior.
- New user flow with stubbed network must cover clear Before/Suggested, one button click = one request with consent, Apply closes panel, quick Undo, no Send and no history/attachment transmission.
- Owner-local acceptance: existing Linux Mint working tree includes intentional `M db/schema.rb`. Never reset schema, delete media/Postgres/Docker volumes, overwrite existing secret or budget ledger, deploy Railway, merge main, or print raw xAI key.

## Prioritized next product milestones
1. **H3e acceptance:** visible responsive UX, accessibility at 320/390/1440px, 200% zoom, no hidden focus traps. One synthetic owner-local Grok request only if they choose; budget and provider response must be reviewed, do not auto-retry.
2. **H3f P0:** make supported text operations (proofread, tone, concise, translate) real with versioned prompts, fixed contracts, validation, explicit action selection and existing budget gates; rename UI presets that are not implemented. No group content sent yet.
3. **H3g/Gate 2D:** structured consent and revocation for participant-approved context, source-linked citations, de-identified audit and production-safe accounting (requires separately approved additive schema and backups).
4. **Gate 3 commercial:** conversation-to-deliverable (client response/proposal/brief), versioned approval, export and pricing validation with small studios. Subscription prices remain hypotheses until paid pilots.

**Business KPI:** successful reviewed edits / successful proposals / accepted deliverables per active workspace, latency, AI cost per accepted output, repeat usage. Avoid vanity counts of UI clicks, generated samples or registrations.
