# ADR — Gate 2B.4: room-scoped writing controls (2026-11-09)

Status: implemented on existing Draft PR #2; exact-SHA CI and owner-local visual acceptance required. Owner screenshots accept Gate 2B.3: manual Apply and Undo restored source without Send.

## Visual and behavioral contract

The conversation composer always shows quiet indicators with accessible text and icons: AI OFF, AUTO OFF, SPELL ON/OFF, preferred preset and one settings icon. They remain visible outside of the manual draft editor. No colored badges or decorative borders; small text and icons supplement real focus outlines. A room-level settings popover reuses the six approved preset IDs, with one native spellcheck toggle. Changes immediately update the composer, the draft editor and the strip. Escape closes settings and returns keyboard focus to the settings icon.

AUTO OFF is an intentionally nonactivating control. There is no model/provider, room consent, approved retention policy or spending cap. Clicking it explains why correction cannot run; it does not turn on anything or create a future automatic opt-in. A selected preset is a style preference for possible future inference, NOT active AI processing. Browser spellcheck is only local spelling hints and can depend on installed dictionaries; it is NOT AI grammar rewriting or translation.

## Browser-only preferences / privacy

Store only the allowlisted data (preset ID from six bundled options, spellcheck true/false) in this origin's localStorage, with key namespaced by authenticated user ID and room ID. Nothing else: no message text, copied draft, attachment content, names, member lists, credentials, server tokens, consent or auto setting. If storage is missing/blocked, default safely to Polish / Clarity + spellcheck on and explain that preferences cannot persist. Invalid payloads are ignored.

This is per-user, per-room, per-browser persistence across page reloads and future messages. It does not synchronize across devices, browsers or account logins. Server-side settings would require a distinct approved authorization + migration stage. The local user-modified db/schema.rb must remain untouched.

## Verification gates

Browser tests exercise persistence across reload, isolation from another authorized room, original composer and FileList unchanged by settings, no message created, no secret draft text in storage, truthful AUTO OFF, keyboard Escape and existing manual editor semantics. Exact-head Rails/Postgres/Redis/ActionCable/two-browser Chrome, Security Audit and Docker Compose must pass. Owner needs to visually accept one screenshot showing composer status and room settings; no main merge or Railway deployment.

Next independent phase, when separately approved: provider-backed AI correction with consent, retention, token/cost limits, debounce/cancel, stale-result protection and explicit Apply → Send. Never silently activate AUTO because a provider becomes available.
