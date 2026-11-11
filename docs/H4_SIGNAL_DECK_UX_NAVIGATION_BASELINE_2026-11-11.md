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
| `/rooms/:id/ai` | Clock icon in the room toolbar | Linked; clock label explains history |
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
