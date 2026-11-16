# ADR — AI Context + optional room instruction V1 (2026-11-16)

**Status:** New development slice in Draft PR #2; exact final SHA CI pending.
No migration, no change to account/room writing preferences, no provider
permission changes, no production deployment.

## Semantics

Room instruction is **low-trust optional user preference data**, not a
trusted system instruction, context consent, evidence, permission to use
tools or right to send. An ordinary Beautify call still receives only the
author's own draft. Contextual Reply/Task only may include a room instruction
when the author turns on the one-request toggle and clicks **Review sources**.

Preview is local, scoped to a private room and authorized under the *same*
all-current-member context access check. The exact instruction text,
revision and bounded set of selected messages are shown before Generate.
The checkbox starts OFF; checking it does not send or spend. A changed
toggle invalidates the signed source preview, requiring new local review.

**Provider payload:** existing code-owned SYSTEM; optional lower-trust JSON
field `room_instruction` containing revision number, text and trust scope.
No extra file, no other room, no tools, no automatic Send.

## Bounds, concurrency and failure policy

Server rejects if no saved instruction, source revoked, current user no
longer a member, content too long (>1200 chars or 4800 bytes), email/token
warning or forbidden control/bidi. Never silently truncate. User-supplied
revision/text/hash are NOT trusted or accepted as overrides.

SourceSelection's signed 10-minute receipt covers permitted message
excerpts, current member roster, hint and the instruction revision/hash
when opted in. Immediately before paid dispatch, server rereads allowed
sources and instruction and revalidates signed receipt; a stale instruction
fails closed without provider call. An existing ledger reservation can be
held conservatively if state changes during the tiny interval between
reservation and last dispatch check; an earlier stale preview is refused
before any reservation. This is not transactionally perfect revocation
while a remote network call is in progress; the production gate requires
a stronger distributed authorization/cost contract.

One-request confirmed paid action remains separate from chat Send. Files
and all-history access are NOT added.

## QA matrix

- No instruction default: no payload, unchanged old contextual behavior.
- Explicit checked preview: exact text/revision, only after consent.
- Cached signed revision invalidated by new version before spending.
- Private-group owner rules, outsider/cross-room/revoked fail closed.
- Invalid flags/sensitive/overlong instructions rejected.
- Provider SYSTEM contains no user instruction; JSON USER input only.
- Two browser UI checks: native toggle, source review gate, no auto Send.
- All four exact SHA CI PASS before local update.

## Next

Full-conversation coverage as an independent consent-scoped snapshot/retrieval
project; input 9 excerpts/2400 chars limit remains and must be disclosed
until truly replaced.
