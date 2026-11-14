# Turbo Chat — AI panel scroll / disclosure motion R2

Date: 2026-11-13. Source: owner's 3 desktop Chrome screenshots for Room settings and Edit draft.

## Fixed
- The workspace header was `position: sticky` with a solid canvas background; while scrolling, it painted a black bar over the moving cards. Both AI sheets now use an in-flow transparent header. Their bounded native dialog scrolling, close button, Esc handling and composer state remain unchanged.
- Secondary conversation settings expand with a native `::details-content` block-size/opacity transition (340 ms, reduced motion supported).
- Expanding a secondary tile no longer switches to `grid-column: span 2`, which instantly moved the neighboring tile. Columns remain fixed, including responsive one-column mode.

## Not changed
- No changes to Spelling hints, Smart replies or Auto correction switches, consent, Grok, draft/Send behavior or user data.
- Browser translation remains optional and local.

## Acceptance
- Scroll both dialogs: no fixed opaque black strip; the top tabs move out of view with content.
- Open/close both secondary settings: progressive height/opacity, adjacent tile stays put.
- At mobile 320/390 px: tiles fit, readable controls, no horizontal overflow.
- `prefers-reduced-motion: reduce` disables these animations.
- CI and user-local screenshots must validate the exact SHA before approval. No merge/deploy is authorized by this note.
