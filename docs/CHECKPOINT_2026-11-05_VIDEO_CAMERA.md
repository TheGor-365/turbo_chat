# Video clip camera UX — 2026-11-05

This is a **short silent video** MVP, not an audio/video call or MP4 uploader.
Hardware mic defect is deferred by owner's explicit request. Real Chrome
may capture still photos using an existing webcam; video clips are 10s max.

- Camera panel now offers Record silent video, Stop video, Discard video,
  in addition to the existing Capture photo and Cancel camera actions.
- No microphone permission requested. Camera tracks closed after stop,
  discard, navigation and error. MediaRecorder flushes final data before
  stopping the capture stream.
- Chrome/other supported browsers: `video/webm;codecs=vp8` with preview,
  350kbps target and 5MB max. A 10s timer stops recording automatically.
- Existing composer controls must not submit while recording. Final Send
  occurs only after preview; draft remains on upload error.
- In-room video player uses private room membership URL and HTTP Range.
- Test: Chrome actual MediaRecorder against animated Canvas.captureStream
  then private room delivery to second browser, without physical webcam
  dependency in CI.
- Still pending: real Linux webcam clip QA, external file upload, audio
  recording repair at end, MP4/transcoding, durable private object storage,
  full professional visual UX.
