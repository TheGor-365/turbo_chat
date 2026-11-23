# G1/B19 — owner QA defects after B18, targeted correction

Date: 2026-11-23 Asia/Yerevan. Base: verified B18 `8dc0a71e5c96a7200895f21261d83caac25fee3a`. B18 Draft [PR #11](https://github.com/TheGor-365/turbo_chat/pull/11). B19 branch: `feat/g1-b19-owner-ux-cleanup-2026-11-23`.

## Confirmed B18 local owner evidence

- Local `review/g1-b18-owner-2026-11-23` with protected ` M db/schema.rb`; private copy SHA-256 `c4b4e5e7cbe53eb0a12bc0f5720a82ed79e31fcc7e2d96a034a82978d2cc643e`.
- JS/CSS built in existing Docker `web` with inspected no-`db:prepare` override. Web-only restart SUCCEEDED. Subsequent HTTP probes `000,000,302` as Puma booted, PostgreSQL/Redis remained running; final `cmp db/schema.rb <private backup>` passed.
- Owner screenshot set: six bottom task tabs work at desktop dark and mobile 400×793; visual state/panels appear. This is **manual partial QA**, not acceptance of Spelling reversibility, saved draft across all tabs, keyboard, light theme, 390×844, or actual provider. Room popover is clipped horizontally on 400px; composer input too narrow due to five buttons in one row. Desktop Status close button inherits native-looking box; Message and Room have inconsistent style picker, extraneous descriptions, source/H4 tasks mixed in Message, Instructions has double borders and no inline current-revision title.

## B19 code changes (require CI and owner recheck)

1. **Mobile layout:** two wide controls above editor for workspace/settings and attachments; second row reserved for only AI action, full-width human editor, explicit Send. Reuses same Stimulus handlers; no extra input or Send owner. Room member popover becomes viewport-bound on narrow screens.
2. **Message/Room UI:** same base style picker classes; remove redundant upfront feedback text (while preserving live status for accessibility), finish caption and document source-claim note; add canonical icon before formatted preview; improve button treatment and Status close.
3. **Translation:** routine enabled status becomes visually hidden but stays accessible; unsupported models/translation errors remain visible.
4. **Instructions:** remove redundant subtitle and extra outline; add edit-pencil inline title to the current immutable revision and library templates. Name changes validate and persist in **existing user-scoped browser-local template storage**, not a new server revision, new DB table, or another participant's title. Blur/Enter saves locally, Escape cancels. Preserve instruction text and optimistic server save/revision tests.
5. **Provider-neutral product labels:** improve/suggest/rewrite/generate display names in RU/EN/ES/HY use AI rather than Grok. Exact provider identity, cost, privacy and per-click consent remain explicit in policy disclosures.
6. **Tasks:** move existing conversation-task and document-review actions to a separately labeled Message-adjacent dialogue workflow card, with original handlers/links intact. Legacy H3 source/evidence DOM is still mounted but visually retired; **Context Studio** stays the source selection owner. Real AI Finalizer generation **not implemented**, old H4 review/export is only a precursor.

## Gates / outstanding

- **CODE_COMMITTED / CI_PENDING / OWNER_RECHECK_PENDING** until exact current head tests and owner mobile/desktop dark/light, dropdown, input/Send, instruction rename/reload, draft, consent and source context regressions.
- Do **not** alter `main`, migrate/prepare databases, edit owner `db/schema.rb`, create or delete volumes, auto-Send, invoke paid AI, or deploy Railway.
- Canonical next milestones: close B19 P1 defects, then G2/D3.2 slim Message/Beautify and G3/D3.3 consolidated Room; G1 isolated PG/media restore required before migration and server-backed context sets.
