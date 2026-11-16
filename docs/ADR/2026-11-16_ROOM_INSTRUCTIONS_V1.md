# Room Instructions V1 — 2026-11-16

Status: implemented in Draft PR #2. Exact SHA CI and user-local rollout pending.

**Security:** Private rooms only. All CURRENT members can read.
Both DM participants may save explicit revisions; only a private group's
CURRENT owner may edit, including after ownership transfer. Outsiders,
ex-members, public rooms and unauthenticated callers fail closed.

**Scope:** Shared room text, up to 4,000 chars and 16,000 bytes.
Never automatically sent to Grok. Not a trusted system prompt, room-context
permission, permission to access attachments, or approval for paid calls.
No new provider endpoints, no automatic sending, summarization or publishing.

**Storage:** New additive migration
`20261116010000_create_room_ai_instruction_revisions.rb`. Append-only
revisions with unique (room, revision_number), editor attribution, change
history; an empty saved revision clears live content but retains history.
Account deletion nullifies the editor reference and anonymizes display as
"Former member" rather than blocking deletion or erasing shared room text.

**Concurrency:** PATCH requires a full {content, base_revision} snapshot,
room row lock and current editor/member ACL. Stale revision -> HTTP 409,
user's draft stays in editor for manual rebase or loading current server
text. Identical updates and empty initial state are no-ops. No auto-save.

**UI:** Room Settings has one collapsed full-width card with text area,
character count, explicit Save, provenance revision number, and manually
opened last 15 revisions. Old text rendered as textContent only. RU/EN/HY/ES;
keyboard/focus and reduced-motion supported. Existing message draft,
account defaults, consent and controls untouched.

**Future:** Effective-instruction preview + explicit per-request opt-in,
provider-scope permissions, included revision/checksum and source citations
before any xAI prompt integration. Do not claim instructions currently
alter Grok's output.

**Local:** Owner's last verified code c06a09c; account migration
20261115230000 already up, local db/schema.rb intentionally modified.
Do not tell owner to merge / migrate until final exact-SHA CI passes AND
a fresh private DB/media backup is made and verified. No main merge,
Railway deploy, volume deletion, or automatic provider spend.

## UX remediation — 2026-11-16

Owner visual review identified a pale/highlighted Save button with low contrast,
stale text remaining in the entry field after saving, and abrupt history reveal.

- Save now uses the established DARK Signal Deck surface/text with an accent
  border and accessible focus, not a pale filled accent with white lettering.
- The editor is an explicit **complete new revision**. After a successful
  server acknowledgment, it clears to an empty entry field and stays disabled
  until new nonempty text. A separately accessible saved-version preview
  preserves the exact current content. "Edit saved version" copies it into
  the editor; this makes replacing/clearing existing text deliberate.
- A conflict, server error or asynchronous user changes NEVER clear the
  unsaved text. A stale 409 requires an explicit rebase or server refresh.
- History and conflict disclosures animate 0fr/1fr in CSS rather than
  immediate `hidden` toggles. Individual versions and saved preview use
  variable-height `details-content` transitions. Reduced-motion settings
  disable these transitions for accessibility.
- History, saved preview and user-authored content remain plain text and
  do not grant context consent, AI calls or automatic chat Send.
