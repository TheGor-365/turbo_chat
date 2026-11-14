# Turbo Chat — AI-enabled messenger capability roadmap / 2026-11-04

The user explicitly requires a complete modern messenger, not a Rails demo.
Local two-account screenshots prove stored two-way messages and visible
private rooms; they do not independently prove both directions arrived
without page refresh.

## Phased feature contract
1. **Real media composer (current):** file picker, OS drag/drop, thumbnails,
   removal, 5 files x 5 MB, accurate errors, draft preservation. Reuse
   existing membership-checked upload and download endpoints. Chrome UI
   acceptance for file selection; manual OS drop remains to be verified.
2. **Camera/still photos:** browser getUserMedia(video), explicit permission,
   constrained JPEG capture, cleanup on close/navigation, picker fallback.
3. **Voice:** getUserMedia(audio) + MediaRecorder capability detection,
   explicit recording controls, preview, duration/size caps, stream stop,
   voice message playback in authorized room, cross-browser validation.
4. **Video clips:** bounded recording/upload, validated MP4/WebM container,
   streaming private playback with HTTP Range; external persistent storage
   and actual restore proof before expensive uploads. Live WebRTC calls
   are a distinct architectural phase, not the same as sending videos.
5. **Messenger functionality:** replies/threading, reactions, delivery/
   unread/read cursors, typing and presence with TTL, file transfer
   progress, accessible search, notifications and mobile offline states.
6. **AI first-class integration:** opt-in invite/mention bot inside a room,
   scoped context, private provider gateway, token and cash budgets,
   streaming, cancellation, audit and safety limits, provider credentials
   only in secrets, no unrequested AI reads of private chat history.
   AI functions include summarization, translation, assistant replies,
   optional RAG on user-approved documents and safe tools. Never claim
   E2EE for provider-processed conversation contents.
7. **Professional custom UI/UX** after core acceptance: use Product Design/
   MagicPath and agree a concept; unified brand/icons/motion/modals and
   complete 320-1440 responsive/accessibility testing.

No paid AI calls, new persistent storage vendor, merge to main, public
Railway deploy or existing customer-data processing is authorized.

Browser API references:
https://developer.mozilla.org/en-US/docs/Web/API/HTML_Drag_and_Drop_API/File_drag_and_drop
https://developer.mozilla.org/en-US/docs/Web/API/MediaDevices/getUserMedia
https://developer.mozilla.org/en-US/docs/Web/API/MediaRecorder/isTypeSupported_static

## Deferred local audio input incident (owner instruction 2026-11-05)
**Deliberately postponed until the end of core implementation; do not repeatedly ask to diagnose it during video/messaging/AI work.** Linux Mint sound settings show PipeWire / built-in audio input selected at 100% with input indicator NOT reacting to speech. User confirms captured voice yields noise, not intelligible speech, across applications, so treat it as a local device/ALSA/PipeWire input problem rather than automatically blaming the Rails recorder. The user has explicitly chosen to resume feature work now and resolve audio at the **final local acceptance stage** before public release. Recheck `pactl list short sources`, `pactl get-default-source`, `arecord -l`, physical ALSA capture card selection via F6/F4, Chrome microphone device, and test OS independent recorder; no system settings changed yet.

**Voice status:** upload/transport/recipient playback accepted in local screenshots; **intelligibility of physical mic NOT accepted**, remains an explicit blocked exit criterion. Do not mark whole voice feature finished.


## 2026-11-09 owner screenshots and queued UX work

User-local screenshots verified six offline presets, Friendly review of two manually selected room messages, disabled generation and preserved Activity/History. Next: Gate 2B.2 non-sending composer draft-safe AI UI. The Home, settings, filter dropdown, favicon and Rails error-page backlog is [UI_UX_BACKLOG_2026-11-09_OWNER_REVIEW.md](UI_UX_BACKLOG_2026-11-09_OWNER_REVIEW.md). Only planned; no mass redesign. Deferred Linux microphone input remains pre-release QA.
