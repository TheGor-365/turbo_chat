# Turbo Chat — attachment upload diagnostics — 2026-11-06

## Owner observation and evidence
- Owner locally fast-forwarded `d57a4ca` to `24b3bfa`, backed up modified `db/schema.rb` to `/home/gor/turbo_chat_schema_pre_notifications_20261106_015215.rb` with adjacent `.patch`, ran `yarn build`, `yarn build:css`, and **successfully applied** `20261106130000_create_notifications.rb` via Docker Compose. PostgreSQL and Redis healthy; the message composer kept a voice `.webm` and `CAREER_STATUS.md` after a failed send.
- Exact Rails logs: `2026-11-05 22:54:14 +0000` `Started POST "/rooms/1/messages"`, `MessagesController#create as TURBO_STREAM`, `Completed 422 Unprocessable Content in 473ms`. No evidence for `500`, database migration failure, or WebSocket failure. The owner-provided filtered logs do not contain the **422 response body**, so the specific failed validator/attachment is **not established**.
- Pre-existing UI `message_composer_controller.js#submitEnd` ignored server `FetchResponse` and always printed `Upload failed. Check file size/type or connection; draft retained.`; this made the real error invisible.
- Rails `AttachmentUploadGuard` already returned a safe text/plain rejection reason; `MessagesController` returned blank 422 for model validation. This is a diagnostic/UX defect independent of notification migration.
- The voice UI showed 0:00 duration, but this alone **does not prove** which file failed validation (WebM codec, duration, MIME, Markdown text, combined upload, etc.).

## Draft PR #2 changes
- `MessagesController#create` now returns plain text validation message on failed model save, consistent with existing upload guard; no file bytes or server traces.
- `message_composer_controller.js#submitEnd` reads and caps safe 422 `text/plain` response (up to 250 characters) and displays it via `textContent`, never `innerHTML`; falls back to HTTP code or connection failure. On rejection, keeps unsent body, reply, and selected files intact.
- Controller tests: rejected fake PNG (spoofed HTML) returns descriptive 422, empty message returns descriptive 422. Real Chrome test uploads spoofed PNG and ensures description appears while draft and file chip remain.
- No DB schema/migration changes, main merge, Railway changes, or paid services.
- CI status on this checkpoint MUST be verified at final HEAD before telling owner to update.

## Next safe acceptance
- After all CI green, owner can `git pull --ff-only`, `yarn build && docker compose restart web`; no migration.
- Re-send only once **after verifying the prior 422 did not persist a message**; if failing, the UI will show the concrete reason and preserve the files. User should report the **exact red text**; fix the actual media/Markdown issue after evidence.
- With a rejected 422, the controller did not report successful persistence; no blanket retry of an ambiguous request prior to checking the full response.
