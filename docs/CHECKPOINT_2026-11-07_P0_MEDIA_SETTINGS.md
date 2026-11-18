# Turbo Chat — P0.3 Video Poster and P0.4/P0.5 follow-up

Date: 2026-11-07 (Asia/Yerevan)
Working PR: https://github.com/TheGor-365/turbo_chat/pull/2
Branch: `feat/security-baseline-2026-11-03`; PR remains DRAFT. Do not merge `main`, deploy to Railway, or modify owner-local databases.

## Changed
- P0.1: message action tray is outside message bubble, concealed until disclosure.
- P0.2: private image lightbox, bounded previews and responsive media.
- P0.3: `VideoWebmPoster` decodes the first real stored VP8/WebM video frame into PNG using local FFmpeg, validates original through `VideoWebmInspection`, limits work to one thread and 8 seconds, output <= 1 MiB, input <= 5 MiB. Server-side Rails.cache keyed to blob key/checksum; no remote encoder or public ActiveStorage URL.
- Poster route `/chat-attachments/:id/poster` shares the current authenticated message-room membership boundary of the original download route. Browser replies have `Cache-Control: private, no-store` and `nosniff`; private room revocation is rechecked even if a derived image exists in server cache.
- Video tag uses its private poster route. Honest `Video clip · press play` affordance; no invented or decorative static stills.
- P0.4: self avatar and label in a single top-navigation account link, label underneath; redundant self profile row removed from sidebar. Peer labels remain.
- P0.5: sectioned Profile / Security / Presence / Notifications form, English camera picker, client-only preview, existing server-side avatar gate and Devise current-password authority unchanged. Global notification controls not misrepresented as shipped; deletion remains a deliberate confirmation action, no automatic deletion.
- Tests: authorized two private room members get real PNG, stranger denied, revoked participant denied after prior view, WebM byte ranges still work, browser video references protected poster URL, navbar and settings assertions updated.

## Testing evidence and open gates
- Local standalone FFmpeg command verified on a generated short VP8 WebM: extracted a real 640x360 PNG.
- Previous branch Security audit and Docker smoke passed; Rails CI identified stale assertions written for the old sidebar.
- **Do not mark the new HEAD fully verified without checking all three GitHub Actions runs.**
- Owner's real Linux Mint Chrome/mobile acceptance and production backup/restore proof remain outstanding.
- No migration or schema changes, no main merge, external deployment or paid resources.

## Next gates
1. Confirm newest HEAD Rails+Chrome, Security, Docker jobs; inspect and repair any failure.
2. Verify fallback on invalid WebM, 320px layout, poster display in two independent Chrome sessions, and membership revocation.
3. User updates own local checkout only after green CI; check WebM playback, poster, account settings, and previously validated DM/realtime.
4. Then proceed with P0.6 acceptance before any P1 reliability or P3 AI provider work.
