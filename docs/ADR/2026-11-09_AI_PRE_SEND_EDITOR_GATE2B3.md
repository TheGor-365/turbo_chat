# ADR — Gate 2B.3: pre-send dynamic editor (2026-11-09)

Status: code implemented on existing Draft PR #2; CI and local visual review required.

## User feedback and strict product split
Owner-local screenshots show an unsent draft in the main room composer and later navigation to a completely separate room history AI Workspace. Both actions had sparkles icons, which obscured the distinction. The previous offline Gate 2B.2 preview showed a static copy but did not actually allow corrections; do not claim owner acceptance.

The room header AI Workspace now uses a clock icon and explicitly says chat history and selected messages. The bottom sparkles affordance opens a floating in-place editor above the composer. Never navigate away from the current room for pre-send editing.

## Working-copy contract

A native spellcheck-capable textarea holds the user's own editable copy. On open, it starts from the live unsent composer text; while the copy remains untouched, typing in the original keeps it synchronized. Once the user changes the working copy, later human changes to the composer disable Apply; explicit Reload is required. Apply updates only the body field after the user's click and leaves reply_to_id and the attachment FileList alone. Undo restores the prior body only if the body has not since changed. Neither action sends a message. Ordinary Send still controls persistence; failed Send retains the draft.

No data is sent to a model, transmitted by a new HTTP request or written to browser storage. Input is plain text, not HTML. Use existing browser spellcheck with honest disclaimer: grammar/semantic AI correction is not yet possible. Preset selections merely record local user intention.

Limits: up to 5000 Unicode characters, 20KB, no invalid control characters. Existing authenticated room-scoped Rails message endpoints and Chrome tests remain authoritative.

## Future model-backed correction, NOT implemented
The final flow will be typing, optional opt-in model suggestion, candidate editable in a working-copy box, explicit Apply, separate Send. Include user consent, provider disclosures, retention limits, spend/token limits, bounded text-only context, cancellation, stale-draft protection, no keystroke billing, no background history access. Never claim real AI grammar quality until verified with an authorized provider.

Exit gate: exact SHA Rails/Chrome/Redis/ActionCable/Security/Docker green and owner screenshots demonstrating editing and Apply/Undo without sending. No main merge, Railway changes, paid AI, new migration, local schema overwrite or media deletion.
