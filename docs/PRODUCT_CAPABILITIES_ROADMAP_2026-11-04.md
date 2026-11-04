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
