# Turbo Chat / Relay Workspace — owner UI/UX review backlog (2026-11-09)

**Status: OWNER FEEDBACK RECORDED — NOT IMPLEMENTED.** Source: screenshots from real Linux Mint/Chrome at 127.0.0.1:3000 on 2026-11-09. User-local fast-forward to commit 53880db and Docker rebuild succeeded; PostgreSQL/Redis were healthy; local M db/schema.rb is intentionally preserved. Jack/Eric are test users. The actual screenshot assets have not been uploaded to GitHub or Drive.

**Design authority:** owner’s latest screenshots and explicit instruction to avoid a big-bang redesign; existing approved Signal Deck / Quiet Canvas style in SIGNAL_DECK_DESIGN_SYSTEM_V1.md and UI_UX_DESIGN_BRIEF_2026-11-04.md. Less decorative outlining, consistent icon family, quiet surfaces, dark/light/system and accessible focus outlines.

## Confirmed findings and proposed repairs

| Screen / component | Verified current state | User-oriented target | Gate |
|---|---|---|---|
| Signed-in homepage / | app/views/pages/home.html.erb is a generic Bootstrap development hero, with repeated routes to conversations and settings; it has no real workspace function. PagesController has a real after_action that changes User.status to offline on normal GET. | **First fix the GET side effect** in a stand-alone tested patch. Then build a functional signed-in Home: continue an authorized conversation, actionably unread activity, recent room links, true authorization-scoped metadata and meaningful quick actions. No fictitious statistics or private snippets displayed by default. | P0 behavioral fix; later D4.5 Home |
| Signed-out homepage / | Same generic Bootstrap hero. | Truthful product entry with first-party brand, concise explanation of real messages/groups/media, exact demo/unavailable limitations, functional signup/login and readable first-run path. No fake SaaS/user/revenue claims. | D4.5 Guest |
| Account /users/edit | Existing avatar/display name/email, new password/confirmation/current password, presence toggle, per-room notification guidance and account removal. Bootstrap card, form-control and outlined fields are not Signal Deck. | Reuse Devise/validation endpoints, restyle into compact first-party Profile, Security, Presence, Notifications and Account removal sections; icons, quiet backgrounds, shared input controls, correct inline errors and keyboard behavior. Preserve current-password semantics. | D5.1 |
| Account completeness | Per-room mute exists; global notification preferences do **not** currently exist. Theme switch is in app nav; other candidate settings are not verified. | Inventory persisted settings and UX. Consider separately: global notification settings, sessions/devices, data export, privacy/block, appearance/locale. No dummy toggles or silent migrations. Each visible control must work or explicitly say unavailable. | D5.2 after backend spec |
| Activity & History /notifications | Actual current-membership scoped search, category chips, room/time filters, pagination, Activity log and authorized history links. The browser-native selects, box density and borders are visually discordant. | Preserve authorized data and live search; later standardize filter selector: accessible native fallback, or an audited custom listbox/popover with keyboard/typeahead/Escape/focus return/mobile behavior. One component first, then reuse. Keep accurate distinction between notifications and full chat history. | D3.2 |
| AI Workspace /rooms/:id/ai | Local screenshots prove offline Gate 2B.1: operation Polish text, preset Friendly, two individual selected messages, displayed rules and disabled Generate. Browser selects differ from first-party look. | Gate 2B.1 **local owner accepted**. Defer dropdown visual polish to shared D3.2 component. Keep provider disabled, selected-only scope, membership ACL. | Accepted function, design queued |
| Browser app icon | public/favicon.ico and public/apple-touch-icon*.png exist, but app/views/layouts/application.html.erb does not explicitly link first-party branded favicon. Screenshot tab looks generic. | Original legally owned responsive mark, SVG/favicons/touch versions and explicit Rails layout link; verify browser tab/light+dark, cache behavior and no misleading copy. Files are existing placeholders, NOT absent. | D0.2 |
| Rails errors /public | 404.html, 422.html, 500.html exist as default Rails static border-heavy gray dialogs. | First-party Signal Deck static errors that load even when Rails is down, self-contained safe CSS/SVG, accurate HTTP status and generic copy; test navigation and no sensitive trace on 500. Audit actual 403/429/empty/offline handling separately, no fake catchall returning 200. | D0.2 / D6 |
| Inputs and navigation | Bootstrap artifacts remain in several unrefined surfaces; native dropdowns show OS styling. | A cohesive low-border icon-led design vocabulary using existing icon helper, quiet surfaces, visible focus rings, accessible names/tooltips and ~44 px touch targets. Do not disable browser focus or replace all selects with inaccessible widgets. | D3 / D6 |

## Home: meaningful information architecture rather than decorative dashboard

For signed-in users, prioritize: (1) Continue conversation, using current participant membership; (2) Unread attention via true server-authoritative existing read state, no new table by default; (3) recent currently accessible chats with minimally necessary metadata, not raw unselected messages; (4) quick actions: Conversations, public discovery, Activity & History, Profile; (5) trustworthy realtime health only when based on the existing connection-health state. Do not render another duplicate inbox or search entire room history without authorization. AI is room-scoped, so an AI entry requires choosing a room first.

For guests, provide a simple branded explanation and working Login / Create account, with honest development/demo status. Avoid claiming a live public production service or hidden AI inference.

## Incremental delivery order and exit criteria

**P0-HOME-PRESENCE:** Inspect the side effect from PagesController#set_status, replace with read-only homepage behavior, HTTP/real-two-browser presence regressions; no data migration. Homepage GET cannot change User.status or broadcast false presence.

**2B.2-AI-COMPOSER (current next feature):** Composer-adjacent AI preview for the user's explicitly entered text only. Do not lose existing body, reply_to or attached File objects. No navigation if it would discard unsent files, no automatic send, storage, paid provider or whole chat context. Continue existing Gate 2B architecture first.

**D3.2-ACCESSIBLE-FILTERS:** Compare styled native select vs accessible popover/listbox, implement one control before replacing any others. Preserve hidden real form fields and URL search semantics. Test keyboard/Enter/Escape/typeahead/focus restoration/mobile touch and screen-reader state.

**D5.1-ACCOUNT:** Audit actual routes and settings. Refactor real current forms while retaining Devise correctness, password managers, labels/errors, avatar checks, privacy controls, deletion safeguards. New backend settings need separate signed-off design and tests.

**D4.5-HOME:** Create functional signed-in hub and separate truthful guest entry, both in the accepted visual system, no new DB by default, and test that every CTA works.

**D0.2-BRANDING-AND-ERRORS:** Original favicon/app icon, app link metadata and static 404/422/500 pages; subsequently review 403/429/empty/offline. Do not assume Rails application layout is available for static failures.

**D6-VISUAL-QA:** Verify 320/390/768/1024/1440 widths, short viewport, dark/light/system, 200% zoom, touch, keyboard Tab/Escape/Space/Enter, contrast, reduced-motion and screen readers. Real screenshot evidence tied to exact SHA and owner approval. Maintain exact-head Rails/Redis/Cable/Chrome/Security/Docker green.

## Non-goals / safety

NO immediate mass redesign, new frontend framework, paid icon pack, external AI connection, database reset, migrations, changes to main, Railway project, Gmail or Drive. No overwriting local M db/schema.rb or deleting Jack/Eric messages/media/volumes. CSS-only success is NOT owner visual acceptance. Keep visual changes on the existing Draft PR #2, and require owner local screenshot acceptance per slice.

## 2026-11-09 checkpoint

- Gate 2B.1 offline preset/review: **owner-local accepted** from supplied screenshots; CI at 53880db green.
- Home, Account, Activity selector, favicon, static errors: **planned only**, not implemented.
- P0 homepage GET status mutation: **code-discovered blocker**, awaiting standalone verified fix.
- Next scoped execution: **Gate 2B.2**, then selective UI slices, release gates as recorded.


## 2026-11-09 owner correction: composer versus history, real-time editing

Owner screenshot shows unsent text in the room composer, then separate /rooms/:id/ai selected-history page. It does **not** show the bottom inline panel's editor, so Gate 2B.2 was code/CI green but visually unaccepted and too weak to address the actual pre-send correction workflow. The identical sparkles pictogram on toolbar/history versus composer caused avoidable ambiguity. User requires a 1–2 gesture, no-navigation, live pre-send correction flow.

**Gate 2B.3 (current, independent):** disambiguate top toolbar into clock/history icon and explicit accessible label; composer icon stays sparkles and opens a floating inline text editor above the input, with live browser-local working copy, native browser spellcheck, explicit Apply and Undo (only current field value) and safe stale-source detection. No suggestion is generated by an AI model. Future AI engine will return a candidate **only into** this editor, then require user Apply → separate Send; eventual token/cost/retention and recipient/consent gates remain separate. Deliver Chrome test for unsent text, reply and attached file preserved; explicit Send remains the sole persistence path.

**Future true AI semantic correction:** opt-in provider / consent / cost cap, bounded 5000-character user draft, provenance and cancellation, debounce or intentional shortcut, stale-response versioning (never overwrite newer typing), latency/loading state, neutral privacy disclosure and per-user manual approval. Do not silently process every keystroke or charge per keystroke. No background room-history read without separate explicit selection.


## 2026-11-09 owner feedback: Gate 2B.4 — room writing preferences and visible status

Screenshots accepted Gate 2B.3 Apply/Undo and the user requested an always-visible compact icon status, room-scoped preferences that survive new messages, and a clear AUTO ON/OFF state. The staged implementation uses browser-local (per user + room) preferred preset and native spellcheck state; AUTO and AI remain visibly OFF because no inference provider, room consent or budget is configured. Settings are compact, keyboard accessible and do not store drafts or messages. The visual scope and acceptance conditions are specified in [2026-11-09_AI_ROOM_WRITING_SETTINGS_GATE2B4.md](ADR/2026-11-09_AI_ROOM_WRITING_SETTINGS_GATE2B4.md). Cross-device sync and automatic AI are NOT implemented. Status: code in Draft PR #2, awaiting exact SHA CI and owner-local visual approval.


## 2026-11-09 owner Gate 2B.5 UX feedback — unify writing control

The room-scoped browser preferences and spellcheck switch persist (owner screenshot), but owner rejected the prior UI: rightmost redundant settings icon; far-off ON/OFF controls; no clear grouped surfaces; generic room/browser scope. New Stage 2B.5 creates a single bottom-left sparkles entry to **Edit draft / Room settings**, status-only strip with no settings icon, explicit authorized room label and detected browser family, short adjacent Bootstrap-toned switches and alternating low-border surfaces. Switching modes must preserve pending manual corrections. AI/AUTO remain OFF, no actual inference. See [ADR](ADR/2026-11-09_AI_UNIFIED_WRITER_GATE2B5.md). Code/CI pending owner acceptance.


## 2026-11-09 owner Gate 2B.5 local evidence and P0 Home presence hotfix

Owner provided Linux Mint/Chrome screenshots of Gate 2B.5 after safe fast-forward `2c8ba0a..fa23791` and healthy Docker web/Redis/PostgreSQL startup. The single left-side sparkles icon, internal Editor/Room settings modes, real Eric/Chrome room scope, tinted grouped surfaces, adjacent SPELL/AUTO toggles and saved Friendly + SPELL OFF indicator are **observed locally**. No real AI correction enabled. This is local functional acceptance; final visual polish is still queued: constrain desktop popover width to content, increase muted microcopy legibility and reduce dead horizontal space, testing mobile/keyboard contrast.

**Standalone P0 correction:** remove PagesController's after_action that writes User.status=offline on every homepage GET. Add request regressions for signed-in online, away and offline (including unchanged updated_at). This is a navigation side-effect fix, not a visual Home redesign. Separate owner-local validation and exact-SHA CI remain required before marking code complete. The active session/logout presence workflow must remain untouched.

Existing work still queued: D4.5 useful authenticated/guest Home; Account; Activity dropdown; branded favicon and static Rails 404/422/500; approved model gateway and consent/cost architecture. Do not treat completed composer UI as authority to enable automatic AI calls.
