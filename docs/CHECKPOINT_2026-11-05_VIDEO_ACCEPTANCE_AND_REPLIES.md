# Turbo Chat checkpoint: video acceptance + reply slice (2026-11-05)

## Owner-local video evidence
- Git feature branch b5e0747 locally updated; Docker Compose web UP,
  PostgreSQL/Redis healthy.
- Sender screenshot: video file attached in composer, live status.
- Recipient screenshot: video message exists with poster frame.
  **Playback motion not independently verified** in supplied screenshots.
- Recipient explicitly shows "Reconnecting · messages synced by HTTP".
  Therefore do not claim a stable WebSocket connection at recipient;
  HTTP fallback delivery works. Investigate recurrent disconnects before
  production, preserving the working fallback.
- Previously agreed Linux Mint microphone issue (hiss/no voice, no capture
  activity in OS) remains deliberately deferred until final local QA.
  See docs/CHECKPOINT_2026-11-05_AUDIO_INPUT_DEFERRED.md.

## Reply vertical slice
- Add nullable self-referential reply_to_id via additive migration. Existing
  messages remain valid; deleting parent nullifies reply_to_id, retaining
  replies. No data deletion.
- Server validates parent belongs to exact current conversation and caller
  is member. Unknown/cross-room target returns generic error without
  leaking quote. Author identity remains server-controlled.
- Composer supports Reply and Cancel reply, keeps unsent text/files and
  clears quote after successful submission only. Quoted context is rendered
  escaped via Rails ERB. Basic accessibility labels.
- Unit/controller/Chrome system test for association, cross-room security,
  preserving draft and rendered quote.
- **Important: do not commit db/schema.rb on this branch while owner has
  existing local modifications.** Additive migration only; owner must use
  `bin/rails db:migrate` in Docker after ff-only pull, inspect schema diff
  before any eventual schema commit.
- This is one incremental messaging slice, not the full final UI redesign.
  Remaining product roadmap: reactions, unread/read cursors, search, AI
  with opt-in room access and budget gate, then full original UI/UX.
