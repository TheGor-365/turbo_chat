# ADR — Unified visual toggles / 2026-11-15

**Decision:** Signal Deck presents a single toggle-switch visual pattern for
all previously visible checkbox controls. The real input remains a native
checkbox when multiple independent messages/sources are selected; binary
settings use `role="switch"` where appropriate. This maintains truthful
accessibility semantics while presenting consistent track/knob styling.

Surfaces audited and changed:

1. Login: `Remember me` (native checkbox submitted through Devise).
2. Room settings: local incoming translation and detailed chat view.
3. AI document/task editor: explicit, unselected single paid-request
   consent. Never prechecked, automatic provider calls forbidden.
4. AI Workspace: scoped multi-message selection; max eight stays
   enforced by client AND server, no new blanket room-history permissions.
5. AI source review: dynamic multi-source selections, no implicit consent.
6. Existing spellcheck/Smart replies/Auto controls are already
   button-based `role=switch`; track dimensions now match.
   
No changes to what is submitted, approval state, source permissions,
provider/API flags, message sends, billing conditions or database schema.

QA: tab/Space input behavior, `:checked`/disabled/focus-visible,
`prefers-reduced-motion`, desktop/mobile, no paid provider calls,
previous input labels and backend permission checks. Future controls should
use the shared `sd-toggle` visual or `sd-ai-room-switch` button contract
rather than introducing raw browser checkbox visuals.
