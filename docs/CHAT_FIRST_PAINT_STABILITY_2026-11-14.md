# Chat initial history reveal (no layout jump)

Problem: scroll_controller delayed initial scroll-to-bottom for two animation frames; the browser could first paint the top of a long conversation, then snap to the bottom.

Changes: set scrollTop immediately on Stimulus connect for ordinary live chats. Use two-frame layout stabilization before removing `data-scroll-phase=pending`; history alone fades in for 160 ms. A 550 ms CSS fallback makes messages visible without JavaScript. Focused search-history navigation still uses its existing bounded scroll and does not auto-mark read. Browser reduced-motion preference disables animations.

Unchanged: room ACL, markup ID and data targets, direct-message draft, send flow, top-level page scrolling, message ordering. This is a code-level fix; a local live reload and visual test are required to validate the reported flicker on user hardware.
