# R1 — conversation-first mode and opt-in incoming translation

Updated 2026-11-13. Draft PR #2, Rails app `turbo_chat`.

## Existing UX audit

Reviewed `rooms/index`, `rooms/_room_container`, `layouts/_new_message_form`,
`messages/_message`, `room_ai_workspaces/show`, the AI editor controller
and service/provider gates.

| Friction | Decision | Status |
| --- | --- | --- |
| AI MANUAL / AUTO OFF / SPELL ON / 2/2 consent / user labels / preset permanently above composer | Hide by default; accessible through **Detailed writing tools** in room settings, persisted only for this browser/account | First code slice |
| Three or more destinations for AI and review in the conversation header | Later group in one understandable **Tools** menu; preserve all routes and direct navigation | Design proposal |
| AI Workspace shows a large consent/policy/cost matrix before "Automatic Client Brief" | Move basic create-brief action first; context and exact sources remain expandable and auditable | Design proposal |
| Separate profile, people search, direct rooms, private/public room discovery occupy constant sidebar space | Progressive disclosure for discover/create, keep active conversations and unread counts obvious | Design proposal |
| Message actions and notification controls compete visually with actual messages | Keep primary conversation controls, disclose advanced actions on activation | Existing pattern; refinement pending |

## Feature: "Перевод входящих" (Incoming translation)

**User model:** Jack writes the original English text. Eric enables incoming
translation into Russian. Eric sees a Russian translation with an explicit
`Translated · EN → RU` label and a disclosure `Оригинал · EN` that expands
the immutable English message. If Eric replies in Russian and Jack enables
English translation, Jack sees English. **The application never sends an
automatic reply as a human**, never edits the sent message, never writes a
translated text to the shared database, and never changes citations or
message signatures. The original survives refresh, search, exports and edits.

**Initial scope:** browser-local `Translator` and `LanguageDetector` APIs.
Opt-in toggle default OFF. Settings belong to the specific logged-in account
in this browser's localStorage (no schema migration); source auto-detection or
explicit source selection, recipient language selection, safe text-only
translation, visible original, fallback to original when unsupported.
Display-only changes are never used as input for H5/AI evidence.

**Privacy and cost:** no external AI transport, no xAI key, no third-party
message API and no paid usage. Chrome may download language packs after
explicit enablement; translation itself takes place on the device.
Messages are not cached to localStorage. Chrome desktop Translator API supports
only some language pairs. It cannot currently provide Armenian, every language
on Earth, universal mobile support, or guaranteed offline model availability.
A future universal provider requires separate, granular cross-user consent,
a hardened provider adapter, durable quotas/billing, data retention review,
a translation cache with invalidation on edits/deletes/revocation, and tests
of operational failure/cost.

Reference: https://developer.chrome.com/docs/ai/translator-api

## Acceptance matrix

- Chrome system tests with a **synthetic browser translator** confirm
  translated incoming text + original disclosure; disabling translation
  restores the existing message, and PostgreSQL source is untouched.
- Initial chat view hides technical status but the original tools remain
  available after enabling **Detailed writing tools**.
- Browser lacking local Translator cannot cause a paid request or erase
  original text. No autopublish, chat message sends, model traffic or
  migration is introduced by this feature.
- Real Chrome native model/language-pack availability and two-account
  Russian/English translations must be verified on owner device. Armenian
  and other unsupported languages are an explicit blocker for full
  "any-language" acceptance.
