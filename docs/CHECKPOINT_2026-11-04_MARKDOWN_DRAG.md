# Owner browser follow-up: room drag/drop MIME feedback (2026-11-04)

Owner screenshot at 22:39 local time:
- `demo1` has green `Live · WebSocket connected` status.
- Dropped file no longer navigates Chrome to the file; composer shows
  `Only JPEG, PNG, WebP, PDF and UTF-8 text files are supported.`
- No filename or browser-reported MIME is visible in the screenshot.
  Earlier owner screenshot opened a local `README.md` in Chrome, making
  Markdown a plausible candidate, not a proven identity for this drop.
- Current backend logs show a confirmed RoomMessagesChannel subscription
  by user ID 2 and a successful HTTP sync with 0 new messages. They do
  NOT show a new POST /messages between the screenshots, so realtime
  delivery of a *new* message is still unverified in this local pass.
- Redis `vm.overcommit_memory` warning is environmental; it does not
  indicate a failed pub/sub subscription, and should not lead to changing
  host sysctl without an observed Redis failure.

Implemented:
- Support `.md` / `.markdown` as inert UTF-8 text attachments, including
  Chrome empty / text/markdown MIME for recognized text extensions. Normalize
  browser text MIME to text/plain and apply existing maximum size and
  server UTF-8, NUL, HTML-signature and full-file checks.
- Keep all other unknown formats rejected. No ZIP/office/video/voice
  formats accepted yet; those require scoped upload policy.
- Better client error naming the unsupported filename.
- CI validates safe Markdown and rejects disguised HTML and uses a real
  Chrome drop with unknown MIME.
- No user database migration, account removal or provider changes.

Acceptance: owner tries dragging small UTF-8 README.md onto message area;
send once and verify authorized download. Two separate browser windows
must show Live connected; send a newly typed unique text without
reloading either window. Report outcome of the second account.
