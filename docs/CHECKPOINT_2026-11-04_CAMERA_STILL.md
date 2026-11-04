# Camera still-photo acceptance checkpoint (2026-11-04)

Feature-branch camera implementation:
- User-gesture-only button; explicit secure-context/mediaDevices detection.
- Prompts for camera permission only when clicked.
- Preview of camera feed, Capture photo and Cancel camera.
- Captured frame bounded to 1280px width, encoded JPEG at 0.82,
  attached to the same existing form and server-side image validation.
- Cancelling, navigating, error and Stimulus disconnect stop every
  MediaStream track and clear the video element.
- Error/permission denial preserves unsent draft. No audio capture requested.
- Browser test for rejected permission and draft-preservation added.

This is **still-photo capture only**; microphone, voice notes, video
recording/video calls are separate work packages. Browser camera hardware
and OS permission dialogs must be manually accepted by the user; CI cannot
prove real laptop webcam availability. No vendor media SDK installed.
