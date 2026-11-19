# Video clip vertical slice — server stage 2026-11-05

Owner-directed next phase after camera photos and voice transport: **video clips**.
Physical microphone in Linux Mint fails independently; user explicitly defers
that diagnosis until the final acceptance. Initial WebM/VP8 clip is therefore
**silent (video-only)**; no claim of recorded speech, calls or AV sync.

Backend stage:
- 5MB file cap retained. Allow `video/webm` multipart with .webm filename.
- ffprobe checks EBML/WebM, one VP8 video stream (no audio), dimensions
  <=1280x720, <=900 packets, <=10.5s, and bounded JSON/timeout. Never
  accept arbitrary codecs or containers based on extension alone.
- Authorized room members can stream bytes via existing private attachment
  endpoint with 206 Range and no-store/nosniff; outsider access remains 404.
- Browser message partial contains HTML5 video player for eligible video
  filenames. Voice clips prefixed voice-* stay in the audio branch even when
  Marcel stores `video/webm`.
- ffmpeg/ffprobe already exist in local Docker from prior voice work.
- CI tests genuine generated VP8 clip, malformed container, audio/videotype
  spoof, >10s rejection, private byte-range and outsider denial.

Next: camera-video UI with permission, 10s limit, cancel/preview/send,
browser test of MediaRecorder against synthetic CanvasStream, and owner
local webcam acceptance. No main merge, Railway deploy or paid storage.
