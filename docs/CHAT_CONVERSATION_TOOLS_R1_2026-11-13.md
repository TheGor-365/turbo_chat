# R1 — Conversation-first header and people discovery

Date: 2026-11-13. Draft PR #2, branch `feat/security-baseline-2026-11-03`.

## Verified baseline

Owner's two-browser Jack/Eric acceptance: incoming English appears to Eric
translated into Russian, `EN → RU` label and original disclosure present.
This is a real Chrome local-model smoke check, distinct from mock CI tests.
No promise of universal language coverage; Armenian is still unsupported by
the browser-only provider.

## Second UX slice (header and sidebar)

**Chat screen default:**
- Display the conversation name, live/reconnecting indicator, and ordinary
  search button (including working Ctrl+K). Keep phone drawer navigation.
- Move less frequent controls into the **Conversation tools** click-only
  disclosure: mute/unmute, sync, AI Workspace, document review (private rooms
  only), and Leave (authorized member rooms only).
- The disclosure is not triggered by hover, does not prefetch private documents,
  remains keyboard accessible, supports Escape and click-outside dismissal.
  Its panel is sized to fit a 320px mobile viewport.
- The existing Rails routes, PATCH/DELETE verbs, server authorization, AI
  consent, and explicit billing confirmation remain unchanged. The menu is
  purely a presentation layer.
- In active conversation, collapse **Find people** into an accessible
  native disclosure. On the inbox/search-results page, keep it expanded.
  Current DM and joined room lists, unread and Activity remain visible.

## Acceptance and non-goals

System tests should prove:
1. Hover does nothing; click reveals secondary controls and Escape closes,
   without clearing composer or creating a message.
2. Mute/unmute survives a Turbo Stream partial replacement inside menu.
3. People search is expanded in inbox, collapsed in chat and expands on demand.
4. No document overflow at 320px while the menu is open.
5. Existing private-group Leave, manual H4 review, AI Workspace, real
   message search, live reception, and permission tests stay green.

This stage does **not** enable paid AI tasks, publish to Railway, merge the
Draft PR, create migrations, or modify existing data/volumes. Further product
stages: reduce duplication in room discovery and surface one plain-language
Client Brief action before source/consent/budget details, followed by a
two-user Share → Review → Approve/Reject workflow with real permissions.
