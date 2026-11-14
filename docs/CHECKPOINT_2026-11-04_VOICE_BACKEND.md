# Turbo Chat voice-message P1 server work — 2026-11-04

Owner confirmed OS drag-and-drop of README.md plus new WebSocket message
visible in incognito without F5 (two local browser screenshots). These
specific P0 media/realtime acceptance criteria are now locally passed.

Voice vertical slice, stage A (backend):
- Limit v1 to audio-only WebM containing one Opus audio stream, <= 60.5s,
  <= 5MB. No Safari/MP4/Ogg promise.
- Guard multipart file content using EBML magic, WebM DocType,
  ffprobe stream codec/type and real packet timestamps with timeout.
  Never trust a renamed video or filename alone.
- Do not permit signed-id direct uploads.
- Active Storage may normalize audio/webm to video/webm. Both persisted
  MIME types are accepted **only after** verified audio-only upload;
  download repeats structural inspection before serving.
- Authorization for playback identical to private chat attachment
  authorization; byte-range responses and no-cache/no-sniff.
- Inline HTML5 audio controls for playback; no external service.
- Install ffmpeg/ffprobe for local Docker and CI, as media inspection
  is a required dependency. Not a public production image.
- Include genuine generated WebM tests, fake container rejection,
  62s upload rejection, private Range and outsider denial.
- Next commit: microphone UI with explicit permission, 60s cap,
  stop/discard, audio preview, real browser-generated WebM acceptance.
- Release gates remain antivirus/media-decoder hardening,
  production object store/backup, external client QA and full design.
