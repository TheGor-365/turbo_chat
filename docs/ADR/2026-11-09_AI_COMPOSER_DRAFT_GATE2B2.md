# ADR / Gate 2B.2 — composer-local AI draft preview (2026-11-09)

**Status:** Implementation pending exact-head CI and owner-local screenshot acceptance. Applies to existing Draft PR #2, following owner-accepted Gate 2B.1. NO generation, model gateway, provider, external call, persistence, new route, table or migration.

## Decision
Show a compact Signal Deck icon adjacent to the already working message composer. On an intentional click, a nonmodal local panel opens within the same form. It displays exactly the text the current author typed, six code-owned preset labels as accessible pressed-state buttons, a visible read-only snapshot and honest status that AI is unconfigured. No fake AI answer or Apply action is offered.

## Privacy and runtime
Only the current browser DOM is read. No fetch(), API requests, localStorage/sessionStorage, analytics, copy to clipboard, data transfer, or automatic chat send. Draft preview is escaped via textContent, not innerHTML; document body never logged. This client preview checks NFC, line endings, bounded 5000 Unicode codepoints / 20000 bytes and rejects unsupported ASCII control characters; its warnings are **advisory only** and do not replace server-side ContentPipeline validation for any future external provider.

No room history, other user's text, member list, attachments, images, microphone or secret settings are supplied to this draft preview. The existing browser form still owns the original body value, reply_to_id, FileList, camera/voice/video panels and send semantics. Close/Escape clears ONLY local preview content, restores focus to trigger, and never changes the unsent composer state. Typing or switching presets invalidates stale preview until the author refreshes. Failed sends keep the draft; successful ordinary Turbo Send clears the preview.

## UX
Use Signal Deck icon helper, quiet surfaces, no decorative card borders, aria-expanded/aria-controls, role group, aria-pressed, keyboard-operable ordinary buttons, aria-live feedback, max-height overflow and mobile narrow styles. These are temporary functional affordances; polished shared dropdowns are a separate agreed D3.2 gate.

## Acceptance and next stage
Chrome: current user may open/close without any message creation; HTML injection is inert; reply and attached file remain unchanged; empty/oversized text not previewed; editing invalidates snapshot; explicit Send uses the existing server-authenticated route and closes preview after success. Require exact SHA Rails/PostgreSQL/Redis/Cable/two-browser Chrome/Security/Docker PASS. Then request owner-local screenshot of panel with a dummy draft; do not ask to upload real private data or credentials.

No merge into main, Railway deployment, paid provider, code migration, change to local db/schema.rb or microphone troubleshooting. Future external inference still requires provider/retention/cost caps and durable room consent.
