# Signal Deck — navigation, controls and H4 UX baseline

Date: 2026-11-11. Reference screen: `/notifications` (Activity & history).

## Product decisions

- User-facing pages must have an obvious navigational entry, not require typing routes. Primary room entry is a labeled icon in the room toolbar; context-specific entry is in the existing `Work with conversation` controls.
- Return navigation is an icon-only arrow-left surface, same geometry as `.sd-activity-back`, with an accessible label/title.
- Prefer existing `sd_icon` glyphs, compact icon actions, quiet surfaces, generous whitespace and fine separators. Avoid Bootstrap-primary calls-to-action, nested generic cards, oversized button stacks and default underlined links as principal UI.
- Consistent picker: reuse the native-backed `sd-archive-picker` interaction from Activity & history; preserve keyboard access, native no-JS fallback and disabled choices. The reusable form version must not auto-submit POST forms when a selection changes.
- Styling must be scoped to the target surface; do not globally restyle select elements or buttons that belong to other workflows.
- Manual H4 review is ephemeral and not approval. Apply, Undo, Send and xAI generation are different actions; neither direct navigation nor review calls a provider.

## Route reachability audit (routes.rb and edited views)

| User-facing surface | Discovery path | Result |
| --- | --- | --- |
| `/rooms/:id` | Rooms list, history | Linked |
| `/notifications` | Nav activity, sidebar history/search | Linked |
| `/rooms/:id/ai` | Sparkles icon in the room toolbar | Linked; distinct from H4 check-check icon |
| `/rooms/:id/ai/deliverable-review` | Check-check icon in private room toolbar; Manual review tool card in AI Workspace; link from Work with conversation | Linked in H4 UX slice |
| Profile settings | Main navigation and sidebar profile | Linked |
| Message search / history source | Search control in room, sourced message deep link | Linked |
| Room consent status `/rooms/:id/ai/context-consent` | JS inside composer (status and consent update) | Service JSON endpoint, not a standalone screen |
| Presence/sync/inbox, source asset routes, `/ai/context-preview`, `/ai/task`, `/ai/draft`, `/ai/reply` | Forms/JS APIs, not page navigation | Service endpoints; not candidates for a page icon |

This is a route-and-template audit, not a dynamic crawl under multiple logged-in identities. Before release, visually verify the new toolbar and modal entrance on desktop/mobile, and test access removal and participant consent revocation.

## Dropdown inventory (edited app/views on feature branch)

| Surface | Visible control | Implementation |
| --- | --- | --- |
| Activity & history | Room and date filters | Existing `sd-archive-picker` (reference) |
| AI Workspace | Task and preset | Shared `shared/signal_picker`, preserving `ai-presets` |
| H4 | Document type and each review decision | Shared `shared/signal_picker` |
| Private group member invitations | Invitee selection | Shared `shared/signal_picker`, required native fallback |
| Chat composer | Hidden task and language native selects | Internal state for custom controls; not displayed, leave separate |

### Privacy and release boundaries

H4 controller rechecks live room membership and unanimous consent on each request and again before returning parsed evidence. No DB migration, persistence, auto-Send, room message write, new external request or Railway release is part of this UI change. `db/schema.rb` on the owner's local machine is not modified.

### Follow-up gates

- Confirm exact-SHA Rails CI, Security audit and Docker smoke on final commit.
- Owner desktop/mobile screenshots: room icon, Work with conversation link, styled AI Workspace tool, H4 back arrow, custom open picker, reviewed item list.
- Keep H7 realtime/presence acceptance independent; investigate if it remains unstable.
- H5 persistent versioning and approval require explicit migration/backup approval.

## H4 result-to-review handoff (added after initial design pass)

- The existing **Formatted Preview** result has a check-check icon action when the current contextual result is `client_brief`, `client_proposal` or `conversation_summary`.
- One user click opens a separate tab first, then performs a fresh consent/status check and a local POST to `/rooms/:id/ai/deliverable-review`. The source tab's unsent draft remains untouched. If the tab was blocked, the action reports an error and preserves the draft.
- The POST transports text and kind only. The server rebuilds authorized room context, verifies all `[M...]` references and membership/consent, parses into ephemeral typed entries and never imports the client's claims as confirmed.
- **Limit:** This is a strict structured Markdown adapter (allowlisted headings and bullets), not a free-form model transcript parser. Unsupported model output intentionally fails closed instead of guessing a safe mapping. A compatibility/normalization contract with tests is required before claiming all generated responses work automatically.
- Review is never Send, Apply, approval, export, storage, generation or an xAI request; no new persistence or migration.
- This change is not end-to-end browser-accepted until verified with a real local result or a controlled synthetic browser fixture; no paid provider call should be made solely for QA.

## H4 format compatibility and offline acceptance

- V1 strict Markdown (known `##` headings plus list bullets) remains supported.
- Offline adapter also accepts code-owned section names as standalone plain lines, Markdown bold headings, an optional document title and ordinary statement lines under an explicit section, including `•` bullets. This covers legacy brief/proposal/summary output without guessing unsupported headings.
- The task prompt now asks for review-compatible `##` sections and `- ` bullets for those three document types; action-item/content-outline workflows are unchanged.
- Unknown explicit headings, code fences, tables, invalid source tags, foreign message IDs, oversized entries and unsupported kinds remain rejected. Cited statements are `inferred`, missing/uncertain statements `needs_confirmation`, never `confirmed` without manual review.
- Browser acceptance without a paid request: navigate to `/rooms/:id/ai/deliverable-review`, click **Try sample · No Grok**, then the compact inspect arrow. The GET renders synthetic text; the POST rechecks current membership and unanimous room consent before constructing ephemeral review entries. Do not use a real provider call to verify this fixture.
- **Acceptance not yet complete** until the owner verifies screenshot of the review result and exact-commit CI (Rails CI, Security audit and Docker smoke). The Formatted Preview handoff requires a real or intentionally mocked contextual result; the sample validates the destination, not an actual xAI transport.
