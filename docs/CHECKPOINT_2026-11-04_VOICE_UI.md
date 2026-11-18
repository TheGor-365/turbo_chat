# Turbo Chat voice message UI/CI slice / 2026-11-04

Prerequisite owner-local evidence: Markdown drag-and-drop and WebSocket
new-message arrival without F5 have been accepted.

Frontend features:
- Microphone button for user-initiated audio-only WebM/Opus recording,
  distinct from camera still capture. No audio recording until clicked.
- Feature detect secure-context, getUserMedia and MediaRecorder.isTypeSupported.
- Stop, discard, 60s cap and <=5 MB. Every microphone MediaStreamTrack
  is stopped on stop, discard, error and Stimulus disconnect.
- Audio preview locally using blob: URL, removable like other attachments.
- No automatic upload or send; existing Send triggers authenticated
  multipart and server-side audio-only ffprobe verification.
- Authorized recipient gets HTML5 playback from membership-checked
  /chat-attachments/:id including bounded byte range responses.
- CSP media-src only self/blob. No CDNs, AI APIs or paid media providers.
- Cross-browser compatibility beyond Chrome WebM/Opus remains out of scope.
  Safari/iOS and MP4 may need a separate validated transcoding pipeline.
- Tests use real Chrome MediaRecorder with synthetic Web Audio oscillator,
  plus mic denial/draft preservation. Physical microphone must be confirmed
  by the owner in real Linux Mint.

If CI fails, diagnose and fix before recommending git pull to owner.
No changes to main/Railway.
