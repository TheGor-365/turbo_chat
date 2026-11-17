# Signal Deck 2 — D1 visual acceptance (pending)

Source standard: owner-supplied `TURBO_CHAT_SIGNAL_DECK_DESIGN_SYSTEM_V2_2026-11-17.md` (17 November 2026).
Baseline: `f4ae7bcb48718423473c11690f2f315081e88199`, existing Draft PR #2. This branch deliberately targets the feature branch, **not** main.

## Changed
- Canonical dark/light/system semantic tokens in `signal_deck_tokens_v2.scss`; legacy aliases preserved.
- Remove duplicate root theme declarations from V1 and refinement; preserve other existing component CSS.
- Remove unscoped legacy 10px white scrollbar; use native application-scoped 6px/ thin scrollbar.
- Standard fields: quiet border with retained keyboard focus-visible outline.
- Room-first screen: shell/canvas tonal separation, readable messages, softly elevated bubbles, consistent avatar geometry.

## Not changed
- No ERB markup, translations, Stimulus controllers, model, route, ACL, consent, AI billing,
  provenance, database migration, server-side send, media or draft behavior.
- No changes to deployment, `main`, Railway or owner-local `db/schema.rb`.

## Human acceptance (NOT verified yet)
1. Compare `/rooms/3?ui_locale=ru` before/after at 1440+ and 390/320 CSS px, dark and light.
2. Verify theme cycle dark -> light -> system without reload and system color scheme transition.
3. Focus standard input by keyboard and mouse; focus visible via keyboard but no persistent neon glow.
4. Send manual message and check both sides, long text, media, reaction, original/translation and scroll position.
5. Open room settings and message settings; ensure no horizontal overflow or broken scrollbars.
6. Verify toolbar, camera/attach, both manual/AI editors and their independent Send arrows unchanged.
7. Check Chrome and Firefox, zoom 200%, reduced motion.
8. Require exact-SHA Rails/Chrome, security, Docker Compose, production-image workflow results and owner screenshots before merge.

Status: implementation proposal for visual review; **NOT production accepted**.
Do not merge or deploy until owner approves the visible room first. Continue with one screen per acceptance.

## Correction after owner review of D1.1 (17 November 2026)

Owner's dark room screenshot rejected D1.1 (unwanted centered 1152px reading column,
extra header card, violet framed composer, dense tiny side labels). The additive
152-line D1.1 override has been **removed**. No substitute max-width was added:
room/header/messages/composer return to the proven full-width flex layout.

Direct changes to existing component files (rather than another cascade layer):
- Canonical input field boundary in its native CSS, no blurred mouse-focus glow;
  a visible flat focus-visible ring remains.
- 14px composer text, 13px sidebar section headings.
- 12px rounded-square avatar corners in sidebar, matching message/avatar roles.
- Prior V2 palette, bubble 15/16px, 12px metadata, and thin scrollbar retained.

**This correction still requires human dark/light/mobile screenshot acceptance.**
It is not a claim that all D1/D2 tasks or security blockers are resolved.

## Owner follow-up — manual composer resizing restored

The owner rejected the D1 modified message input. Restore the original borderless 13px
composer styling, retain its existing resizing grip, and make the grip available in
ordinary chat mode (not only during Beautify compare). The controller now preserves
manual height across typing, clears custom height only on successful Send, and never
calls Grok from dragging or keyboard sizing. Native Rails/Hotwire message handling is
unchanged. The geometry system test now authenticates through Devise, checks the
room and the grip, and verifies manual size survives typing without a send.

Next UI acceptance surface per the design specification: existing Message Settings
and Room Settings sheets. No current acceptance claimed for those screens.

## Screen 02 — Message settings / #ai-draft-panel (visual acceptance pending)

- Localized title and All/Hide styles disclosures in ru/en/hy/es.
- First three existing writing presets appear as compact shortcuts, sharing the existing selection controller; original full six-preset list remains unchanged inside native details.
- Existing local Preview/Apply section appears before advanced AI actions, with unchanged handlers and no automatic sending.
- Advanced action tiles are denser, while consent/cost/source information remains available.
- Only #ai-draft-panel is restyled: no Room Settings, Rails/ACL, database or external AI behavior change.
- QA: expand all six, select any, preview and apply only to unsent draft, keyboard/Escape, 320/390/1440 dark/light; no owner acceptance assumed.

## Screen 03 — Room settings / #ai-room-settings (visual acceptance pending)
- Visible localized title and read-only live summary of actual current profile, writing language and writing style (ru/en/hy/es).
- Existing versioned room instruction disclosure is presented as “Conversation goal” above writing preferences **only for private rooms**. No new field, no new room instruction storage.
- Existing quick profiles, style, tone, opt-in member permissions, disabled Auto Reply and details remain functional.
- Additional display/translation settings remain native disclosures; accessibility, provider consent and UI/runtime language are kept distinct.
- Updated older Chrome test to assert visible titles, not obsolete visually-hidden elements.
- Do not interpret the summary as AI readiness or implicit consent. Dark/light/mobile owner acceptance required.

## D4.1 / Review Document — first-screen localization, visual check pending

The existing review page header, privacy notices, editor type, Markdown field and primary action are now localized en/ru/hy/es. Controller-generated notices are localized. The primary review button displays a visible action label instead of an icon only. All existing GET/POST routes, authorized source links, review-state decisions, save form, comparison workflow and parser-defined Markdown syntax remain unchanged. **The lower Review/Save/Compare sections still need full I18n and visual conversion** before D4 can be accepted. No modal wrapper, new persistence or deployment. Added Russian GET smoke test; next human check is the existing `/rooms/:id/ai/deliverable-review` page.

## D4.2 / Document Review — lower sections localized

Localized statement decisions, status/section labels, source links, save and compare controls in four supported UI languages without altering source message content, evidence permissions, form endpoints, CSRF tokens or Markdown parsing. RU POST integration test now checks the review and Save action. No modal transport or new persistence yet; owner acceptance still pending.

## D4.3 — Document Review TaskSheet visual layout (owner acceptance pending)

The existing deep-link page now presents an inline compact TaskSheet composition with three anchored sections, factual count of authorized source IDs (only when the validated document exists), a native privacy disclosure, a responsive side-by-side document/review layout and an optional native Compare disclosure. Existing GET, POST, CSRF-formaction, Save, review decisions, source links and permissions are unchanged. No modal opener, Turbo frame interception, or unsaved-draft persistence has been introduced; these need separate implementation and browser acceptance. The Compare form remains in the DOM but is revealed with native `<details>`; older system coverage now expands it before checking visibility. Owner to validate desktop dark/light and mobile widths before any modal transport work.

## D4.4 — Native modal presentation (owner acceptance pending)

A native `<dialog>` now opens the existing authorized review from the room Tools menu, the composer link and AI Workspace, without framing: CSP deliberately has `frame-ancestors 'none'`. The controller fetches same-origin HTML, imports only the existing `#h4-manual-review`, and sends its actual Rails POST forms (including the H5 target-specific submitter CSRF token) with `FormData`. It handles 403 by clearing displayed evidence and requires a confirmed H5 show response before stating a draft was saved. External content, scripts, caching, sessionStorage, automatic model calls and Send are absent. Source and demo links open a separate tab so they cannot replace the unsent chat. Closing/Escape discards only ephemeral modal content, returns focus to the originating action, and leaves the chat composer untouched. Native links still work as GET without JS. *Explicit generated Preview → Review currently still opens its existing separate POST tab; do not reroute it without its own security and draft-preservation tests.* No server model/controller/routes/CSP/database change. Browser acceptance needed before merger.

### D4.4 test correction

The native modal's translation object is read from the dialog target (not the body scope). Use `FormData(form, submitter)` only with a real submitter, preserving H5 action-specific CSRF. Unexpected successful non-review HTML now clears stale review evidence. Added Chrome system coverage for opening from the real room menu, reviewing a one-statement document via POST without sending a chat message, closing the modal and preserving the original composer draft.

### D4.4 H5 Save integration gate

Added browser coverage for saving from the modal with Rails forgery protection enabled; validates the endpoint-specific submitter CSRF token through actual H5 storage and confirms that the room composer draft and message count remain untouched. Saving is an explicit user action only.

## D4.5 — AI Workspace task hub and complete screen UI i18n (owner acceptance pending)

Deep link `/rooms/:id/ai` remains native Rails GET and POST preview. The workspace starts with four task cards (reply → original room, summary → current selection form, document → existing review, sources → current message picker), not fake new actions. Saved drafts and paid generation are compact secondary links/status; disabled AI is visibly unavailable without pretending provider readiness. Details disclose consent, context and exact budget only when requested. All visible screen copy, counts and picker descriptions use dedicated RU/EN/HY/ES UI keys; displayed message content and canonical operation/preset IDs are never translated in the payload. Existing 8-message limit, evidence consent, form and preview endpoints, access, CSRF, no-provider behavior stay unchanged. Browser-owner acceptance of dark/mobile/light remains required. No deployment or database updates.

### D4.5 allowlist correction

The first-party `SignalDeckHelper::ICONS` does not include arbitrary Lucide names. New task glyphs were replaced with existing allowlisted glyphs (pencil, messages, chevron-down, search, file-text); the icon helper's static allowlist was not widened. Russian integration smoke verifies SVG rendering of the new task hub.

### D4.5 content consistency

Removed a hard-coded `Automatic Client Brief` prefix in localized document task. Rendered preset details and JS-generated option metadata now translate user-facing tone/style/audience labels while retaining the unmodified underlying canonical metadata and submitted operation/preset IDs. Human-readable review flags are translated by explicit mapped copy. No server parameter or model behavior is changed.

### D4.5 CI review corrections

Rails I18n reserves `locale:` as the call-level locale selector. The visible preset language now uses interpolation `language:` so any previewed EN preset still renders inside RU UI without raising 500. Restored the historical English accessible name `Open saved documents` through a dedicated localized aria key to keep legacy bookmarks/test selectors stable. Added RU POST coverage for a translated technical preset without changing operation or preset IDs.
