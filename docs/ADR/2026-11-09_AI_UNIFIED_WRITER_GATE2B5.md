# ADR — Gate 2B.5: unified writer workspace and compact controls (2026-11-09)

Status: code and Chrome acceptance tests submitted in existing Draft PR #2; exact-head CI and owner visual verification required.

## Owner evidence and correction
Owner visually confirmed Gate 2B.4 browser-local room preset persistence and SPELL OFF, but rejected its spacing and semantics: a second settings icon at the right of the composer created two entrypoints to the same writing tool; switches were visually detached from their names; section boundaries were too weak; the scope said only "this room / this browser". Do NOT claim Gate 2B.4 visual approval.

## One left-hand entry and no lost draft
Only the existing **bottom-left sparkles** control opens the writing workspace. The rightmost settings icon is completely removed, leaving a read-only status strip (AI OFF, AUTO OFF, SPELL ON/OFF, chosen preset). In the floating workspace, two compact, clearly labeled modes **Edit draft** / **Room settings** replace two external entrypoints. The original manual Apply → Undo → Send contract is retained. Switching modes preserves a not-yet-applied editor working copy, its source revision, the reply target and FileList; closing the workspace discards only the unapplied working copy. Escape returns focus to the left-hand icon. Submission success closes the workspace.

## Visual scope
The settings view shows the **current authorized room's display label** (peer chat_label in DMs; room name for groups/public rooms) and the browser family derived from the current browser User-Agent, explicitly marked "this device". Neither value is persisted. Separate soft-surface groups define style selection and assistance switches, using alternating tones instead of borders. Each assistance row keeps icon, short name and switch adjacent and uses the project's Bootstrap-oriented primary/success colors for active selections and the ON track; OFF has a neutral track. Keyboard focus is still visibly outlined, mobile popover scrolls within viewport, and reduced-motion is respected.

## Honest OFF and storage boundary
AUTO remains **OFF**, with an informational switch-like control; clicking only explains missing provider, consent and spending caps. Browser spellcheck is on/off but may require a browser dictionary. Six presets are future inference preferences, not active AI corrections. Persist only allowlisted preset ID and spellcheck boolean in the existing origin localStorage key scoped by user and room; never store room names, browser information, drafts, attachments, keys, consent or automatic processing settings. No backend changes.

## Verification / non-goals
Chrome acceptance must cover one external icon, real scope text, both modes, preserving an unapplied working copy while switching, persisting selected settings across reload and distinct rooms, no false AUTO, no auto-send and all older reply/attachments. Run exact SHA Rails, Redis, ActionCable, two-Chrome, Security and Docker CI. Do not merge main, deploy Railway, touch user's local M db/schema.rb, reset volumes or add paid provider integrations. Other Home, Settings, Activity, dropdown, favicon, 404/422/500 polish remains in backlog.
