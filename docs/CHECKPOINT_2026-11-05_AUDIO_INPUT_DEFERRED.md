# Deferred Linux Mint microphone audio fault — 2026-11-05

## Source and owner decision
- Real local Chrome screenshots: two accounts exchange WebM voice attachments, and a 9-second recording can be previewed and attached; recipient displays an HTML5 audio player. WebSocket for chat connected.
- Owner reports background hiss with no discernible voice in all tested apps.
- Linux Mint Sound > Input screenshot: Built-in Audio microphone at 100%, nearly no capture-level activity while speaking.
- `alsamixer` screenshot shows **PipeWire virtual card** with Master output slider, NOT a selected physical ALSA capture card. Hardware configuration remains unexamined.
- **Explicit owner directive:** defer further audio debugging until after remaining application features; keep this as an open P1 acceptance blocker and continue the plan.

## Mandatory return gate before release
1. Run `pactl list short sources`, `pactl get-default-source`, `arecord -l` and identify hardware microphone source.
2. Select physical capture card in `alsamixer` (F6 then F4); test Linux Mint sound input outside the browser, adjust channel/mute and only cautiously mic gain.
3. Confirm clear local recording outside Turbo Chat, then Chrome captured WebM, then second authenticated browser playback. Reject if only noise remains.

## Current decision
No ALSA/PipeWire system configuration changes now. Do not change Rails microphone code without evidence of an app-specific defect. Preserve all local data; never modify main, Railway or paid services for this incident.
