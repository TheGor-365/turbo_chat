# R1: modal-first error UX and safe HTML fallback

Date: 2026-11-13. Applies to Draft PR #2, not a public deployment.

## Decision matrix

| Scenario | UX | Server contract |
| --- | --- | --- |
| HTML navigation / form denied, no response body | Native modal over current Turbo page | Original HTTP 4xx/503 plus X-Relay-Error-State |
| Direct address-bar visit to a forbidden/missing URL | Branded Turbo Chat fallback, link to conversations | Original HTTP 403/404 |
| Composer upload validation or text errors | Existing inline composer error; draft retained | Existing 422 Turbo Stream / redirect |
| AI Workspace selected-scope validation | Existing inline feedback inside review panel | Existing 422 rendered review |
| JSON API and background AJAX | Consumer handles existing machine status | No injected HTML |
| Turbo Stream responses | Existing action-specific text/stream behavior | No injected HTML |
| Avatar/image/voice/video attachment responses | Existing media behavior, raw 404 etc. | No injected HTML |
| Production framework exception / service outage | Existing branded static 404/422/500 fallback; no JS dependency | No fabricated success |

A single UI layer handles status 400/401/403/404/406/409/410/422/429/503 for browser HTML actions. Room-specific title is shown without disclosing names; AI-permission context appears only for a member already authorized to see that room. No request IDs, text excerpts, personal data, or tokens enter the error header or popup.

The Stimulus dialog listens to Turbo fetch responses tagged by the server, cancels replacement with the error document and keeps the current workspace rendered. A **new direct browser navigation has no previous DOM**, so a branded fallback is necessary. Native dialog gives Escape, focus trapping and restoration; a Close action does not navigate.

## Acceptance and limits

- Request tests: 403/404 body, exact status, no private text, JSON/Turbo Stream/attachment bypass.
- Chrome system test: revoked H5 consent from saved-documents navigation opens the dialog, dismisses and preserves original URL.
- Do not intercept normal successful responses, binary streaming, or provider errors with their own inline UI.
- Does not authorize a new paid AI request, change ACL, create accounts, deploy, update schema or alter any user data.
- True network failure or a crash outside Rails cannot magically produce a modal from this application; existing independent static error pages remain the fallback.
