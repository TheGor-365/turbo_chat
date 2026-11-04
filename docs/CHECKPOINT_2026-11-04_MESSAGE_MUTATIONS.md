# P1 checkpoint — author-only message mutations

Date: 2026-11-04. Branch: `feat/security-baseline-2026-11-03`, draft PR #2.

Delivered a minimal vertical slice: own message text edit and delete via
nested room/message routes. Controller verifies Devise identity, actual room
membership and message ownership on every operation. Update permits only body,
never author ID or attachment mutations; Rails validations apply. Existing
write throttling extends to edits/deletions.

The room partial now renders owner-only Edit/Delete controls. Turbo Stream
append/replace/remove events are delivered to **per-recipient authorized room
streams**, with each recipient's view rendered separately to prevent the wrong
member's controls from leaking into another viewer's markup.

The editing form is a conventional full-page screen; inline editing is deferred
to the UX phase. HTTP request tests cover success, owner authorization, outsiders,
validation, and owner-only controls in rendered HTML. Realtime behavior requires
the existing two-Chrome-client system acceptance and dedicated edit/delete E2E
tests before release. Not production approved.
