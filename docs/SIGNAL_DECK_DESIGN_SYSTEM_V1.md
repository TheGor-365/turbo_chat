# Signal Deck — Product UI/UX Design System v1.0
**Product:** Turbo Chat / Relay Workspace · **Decision:** owner approved Signal Deck on 2026-11-06 · **Status:** approved direction, implementation in stages; NOT a claim of finished UI or production release.

## 0. Product strategy and non-negotiable constraints
Build a premium, mobile-first messenger/workspace interface with light, dark, and system themes, low visual noise, dense functionality, expressive but consistent 24-grid line icons and quick direct actions. **Design system ≠ Bootstrap skin.** The eventual UI must have its own tokens, components, interaction contracts, accessible states, responsive shell, and verifiable QA. No legacy Bootstrap form visuals in the completed system.

Preserve all existing Rails 8.1/Hotwire/Stimulus server semantics: Devise account/security, typed and voice media, attachments, replies, reactions, edit/delete, search, unread/read-cursors, private DM ACL, real-time delivery, presence privacy, notifications. No direct DOM insertion of untrusted HTML. No visual work may bypass current authoritative HTTP/Action Cable controls.

**Interaction rule:** replace conventional form *presentation*, not semantic native controls. A keyboard, IME, screen reader, password manager and browser autofill must still work. Avoid icon-only controls when meaning is uncertain; reveal context with tooltip, title, labels, and confirmation when destructive.

## 1. Product IA and priority
Primary tasks: (1) open/continue a conversation, (2) send/reply/attach/record, (3) find contacts or a room, (4) manage notifications/presence, (5) manage account and preferences. Each should be reachable within 1–2 direct actions from its appropriate context, not a long form.

| Surface | Mobile compact (320–767) | Tablet (768–1023) | Desktop (1024+) |
|---|---|---|---|
| Global navigation | 52–56px top utility bar; 44px targets; icon + accessible name | 56px compact header | 60px header with optional labels |
| Inbox / contacts | Full-width single pane | 280px conversation rail | 304–344px conversation rail |
| Conversation | Full-width when opened, explicit back-to-inbox | Remaining pane, flex min-width:0 | Remaining pane, optionally details drawer |
| Secondary panels | Bottom sheet / full-screen modal | Popover / modal | Anchored popover / details side drawer |
| Composer | Sticky bottom safe-area-aware dock | Dock under messages | Dock under messages |

Never render two vertically stacked full-height panes on compact widths. On compact screens, `/rooms` = inbox; `/rooms/:id` = conversation, with a clear Back control. `100dvh` and `env(safe-area-inset-bottom)` only in bounded workspace; settings, auth, landing use native page scrolling.

## 2. Foundations: raw scales and semantic tokens
**Naming:** `--sd-*` (Signal Deck), no arbitrary inline colors. Theme values via `:root[data-theme="dark"]`, `:root[data-theme="light"]`, `:root[data-theme="system"]` + media query.

**Palette (initial reviewed candidates, refine against screenshots/contrast):**
| Semantic token | Dark | Light | Use |
|---|---|---|---|
| `--sd-canvas` | `#0c121c` | `#f6f8fc` | app background |
| `--sd-surface` | `#121b28` | `#ffffff` | main panels |
| `--sd-surface-2` | `#1a2635` | `#ecf1f8` | cards and hovers |
| `--sd-surface-3` | `#243246` | `#dfe7f2` | selected row |
| `--sd-text` | `#f1f5fb` | `#152235` | normal text |
| `--sd-muted` | `#b0bfd2` | `#52647b` | secondary text |
| `--sd-border` | `#334258` | `#cbd6e5` | thin dividers |
| `--sd-accent` | `#91bcff` | `#235bd5` | active/links |
| `--sd-accent-strong` | `#245bd7` | `#235bd5` | primary surfaces |
| `--sd-on-accent` | `#ffffff` | `#ffffff` | text over accent |
| `--sd-success` | `#4ed6a0` | `#167d60` | online/success |
| `--sd-warning` | `#f5c56b` | `#966417` | away/alerts |
| `--sd-danger` | `#ff8f98` | `#b42336` | destructive actions |
| `--sd-focus` | `#bad4ff` | `#235bd5` | visible 2px outline |

**Spacing:** 4px base; `--sd-space-1..8`: 4/8/12/16/20/24/32/40px. Mobile page gutter 12–16px, desktop panel gap 12px.
**Radii:** 8px control, 12px panel, 16px sheet, 24px feature; pill=999px. No indiscriminate full-round cards.
**Typography:** system sans stack with `Inter` if installed; body 14px/1.5, chat text 14–15px/1.5, meta 11–12px, heading 17/22px semibold, large brand headline 28–36px. Never use color alone for status.
**Elevation:** `--sd-shadow-floating` for menu/sheets; quiet 1px separators; avoid thick gradients or glass everywhere.
**Motion:** hover/press 120–160ms; sheet 180–240ms; no decorative bounce; respect `prefers-reduced-motion`.
**Iconography:** coherent self-contained 24×24 stroke family, actual glyph 16/18/20/24px; control hit box 40–44px minimum, mobile primary targets 44×44px, destructive actions separately confirmed. New icons go through one helper/component, not mixed-font ad hoc emoji.

## 3. Core component contracts (ERB partial + tokens + optional Stimulus)
| Primitive | Required states / behavior |
|---|---|
| `sd-icon` | allowlisted name, SVG `aria-hidden`, size; parent controls carry action label |
| `sd-icon-button` | hover/focus/pressed/disabled/loading; tooltip; >=44px target on touch |
| `sd-surface-field` | native email/password/text with stable `label`, autocomplete, inline validation, keyboard IME |
| `sd-segmented` | 2–4 exclusive options, `aria-current` or radio-group semantics, focus order |
| `sd-chip` | filters are toggles with named accessible state; no hidden action |
| `sd-avatar` + presence | stable accessible identity and secondary status label |
| `sd-command-search` | search icon, keyboard clear/Esc, recent/results, bounded server query, empty/error |
| `sd-composer-dock` | native input under rich shell, autoheight, file/voice/camera/send; actions never lose existing draft |
| `sd-message` | incoming/outgoing, timestamps, attachments, reply context, hover/focus actions, reactions |
| `sd-sheet`/`sd-popover` | Esc/backdrop dismiss, return focus, trap focus for modal sheets, scroll-lock only during open |
| `sd-menu` | roving or ordinary keyboard activation, focus restore, contextual actions |
| `sd-toggle` | binary UI with actual labelled checkbox or button/pressed state |
| `sd-toast` | polite/live-region progress, retry for recoverable errors |
| `sd-skeleton`/`sd-empty` | usable loading/empty/error/offline states without infinite spinners |

Implementation home: `app/helpers/signal_deck_helper.rb`, `app/views/ui/`, `app/assets/stylesheets/signal_deck.css`, `app/javascript/controllers/theme_controller.js` and later bounded component controllers. Build with existing esbuild/Sass; do not add a JS framework or CDN.

## 4. Input interaction patterns replacing Bootstrap form presentation
1. **Chat composer:** dock with editable surface, attach, emoji/reactions, camera, microphone and send icon. Enter sends only when not composing IME; Shift+Enter multiline. Existing reply remains a compact context capsule. Enforce file-type/size on server as before; expose upload/error/retry states.
2. **Search:** command surface, always keyboard-accessible search input; Escape clears/closes overlay; debounced server-side scoped search. Mobile search opens sheet; desktop anchored popover. Never auto-leak private room matches.
3. **Discovery:** users/rooms/unread as compact rows; filters are chips or segmented buttons, not dense input grids.
4. **Settings:** cards for avatar, display name, presence, per-room alerts, account/security. Destructive actions separated at bottom. Preserve Devise current-password semantics until an explicitly designed and tested secure alternative exists.
5. **Authentication:** own surface fields, show/hide password control, clear per-field validation, autofill/password-manager support, no unlabelled floating placeholder-only fields.
6. **Media:** attachment options via action sheet; capture, preview, confirm; microphone permissions never silently requested on page load.

## 5. Screen and state inventory
- Marketing: welcome/feature demo/CTA, not claims of production availability.
- Auth: log in, sign up, recovery request, reset, auth errors, password manager/autofill.
- Workspace: empty conversation, contacts/inbox, direct room, public room, room discovery, notifications.
- Chat: empty history, long history, unread, search overlay/hit, reply context, edit/delete, reaction picker, upload image/document/audio/video preview, playback, webcam/mic denied, offline/sync/reconnect.
- Profile: avatar preview/error, display-name update, presence privacy, notification preferences, account change/delete confirmation.
- Popovers/modals: command search, user overflow/actions, emoji, attachments, mobile back, settings and errors.
- States required in each: idle, hover, focus-visible, pressed, disabled, pending, success, empty, error, offline, reconnecting, reduced motion.

## 6. Theme/locale/content contracts
Dark/light/system theme uses one `data-theme` preference on the root element; browser-local persistence with storage failures ignored. Default to dark for continuity with the current owner-local demo; users may choose light/system. System mode follows OS changes without a server round-trip. Themes must cover chrome **and screen content** before claiming full rollout. No inline untrusted CSS.
Language: RU/EN copy strategy later, but layout tolerates longer labels and Cyrillic/Armenian user names. Maintain LTR now; avoid unsafe truncation. Honor zoom 200% and screen-reader labels.

## 7. Quality and operational acceptance
**Feature safety:** no route, Action Cable event, permission policy or attachment behavior regression. Server ACL and validation never depend on client theme.
**Visual:** 320, 390, 768, 1024, 1440; desktop/mobile screenshot pairs in both themes; no clipped controls/horizontal page overflow; short 640px viewport.
**Accessibility:** WCAG 2.2 AA minimum target sizes, tested focus rings, form labels, keyboard flow and sheet focus restoration. 44px touch target is product design target, not mislabelled as the WCAG technical minimum.
**Performance:** one first-party CSS layer, no external icon CDN/fonts, minimize layout shifts, avoid continuous animation. Avoid duplicative real-time subscriptions.
**Functional:** signed-out auth; two signed-in Chrome browsers; DM typing/presence/unread, search, media, notifications; switching theme preserves draft and scroll. Run Rails, Redis, Chrome and Docker smoke CI after each vertical slice.
**Release:** user visual acceptance, security review, controlled deployment only after separate approval. No direct merge to `main`, Railway changes, billing or publication here.

## 8. Migration/implementation gates (track individually)
- **D0 — approved:** Signal Deck selected; this spec, inventory and source references.
- **D1 — foundation:** tokens, first-party icons, preference controller, adaptive global nav. Acceptance: light/dark/system persisted across routes; keyboard accessible; Rails/Chrome CI green.
- **D2 — workspace shell:** single-pane mobile inbox/chat with back link, bounded flex scrolling and safe-area composer; tests at 320/390/768/1024/1440.
- **D3 — interaction primitives:** command search, segmented filters, alerts, sheets/popovers, core custom fields and accessibility.
- **D4 — messaging:** send/reply/reactions/actions, media surfaces, error and connection states; preserve all existing features.
- **D5 — account + auth:** redesigned settings cards/Devise forms including valid password flows.
- **D6 — motion & QA:** screen/state inventory, theme parity, contrast/keyboard/zoom/reduced motion, real screenshots and video.
- **D7 — showcase:** separate owner-approved Railway project, privacy/security QA, truthful RU/EN case, Drive evidence manifest.

**Do not mark a later gate complete because its CSS file exists.** Owner local screenshots and actual CI are source of truth.

## Design-research references (patterns only, no visual cloning)
- W3C WCAG 2.2 SC 2.5.8 target-size minimum (24px minimum or permitted spacing exceptions): https://www.w3.org/TR/WCAG22/#target-size-minimum
- W3C WCAG 2.2 keyboard focus and focus appearance: https://www.w3.org/TR/WCAG22/#focus-appearance
- Android adaptive navigation patterns (bottom on mobile, rail/sidebar at wider widths): https://developer.android.com/design/ui/mobile/guides/layout-and-content/layout-and-nav-patterns
- Linear Inbox docs (dense prioritization and clear selected states, not a source for copied UI): https://linear.app/docs/inbox

**License note:** no external visual assets, copied brand logos, icon font downloads or paid resources are introduced by the spec. Any future third-party icon/font incorporation requires license attribution and allowed bundling.
