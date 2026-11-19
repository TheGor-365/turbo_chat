# AI Composer UX V2 — One-message generation options (2026-11-15)

Status: implemented in Draft PR #2; exact-SHA CI and owner-local acceptance pending.

## Contract

- Quick result row replaces the static "AI generation" label with two accessible icon buttons: Regenerate and Generation Settings.
- Composer ordering: Beautify first, then Draft Editor, Camera adjacent to File attachment, microphone after them. Existing attachment validation and transport remain unchanged.
- Settings drawer controls **only this generation**: style, output language, tone. They never overwrite saved room preferences. Server validates fixed allowlists and adds code-owned instructions; user input is never treated as a system prompt.
- Regenerate is disabled before a successful response and whenever current options match the latest successful request. Editing options alone never spends tokens. Reverting restores a previously attested AI result (if still available); the primary Beautify trigger cannot silently duplicate a successful request.
- Original draft and AI suggestion remain separate. AI Send requires the exact successful options snapshot and valid provenance; options changes or pending requests disable it. Neither option selection nor generation sends a chat message.
- No new account-wide defaults, automatic requests, room-history sharing, file access or stored AI bodies in this slice. Existing 2/min throttle and LocalBudgetLedger limits remain. A failed outbound request may still incur cost.
- The quick toolbar intentionally exposes five own-draft writing presets; the translation-specific advanced preset continues to require its explicit target locale.

## Acceptance
- Automated browser: unchanged snapshot -> disabled; change tone -> enabled; revert -> disabled; then one explicit regeneration with changed payload; no chat send; controls ordered as specified.
- Server: precise options in code-owned system prompt; invalid values rejected; no extra AI authorization.
- Review real desktop/mobile owner screenshots and exact SHA Rails/Chrome/Redis/security/Docker checks before acceptance.
- No migration, main merge or Railway deployment authorized.
