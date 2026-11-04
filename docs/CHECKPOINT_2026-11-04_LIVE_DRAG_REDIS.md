# Live media regression — owner evidence 2026-11-04

Confirmed with real two-user Chrome screenshots on Linux Mint:
- Webcam permission, actual camera feed, Capture photo, private file upload
  and reloading of message history work.
- OS drag-drop **outside the form** caused Chrome to open the file.
- Recipient only saw the newly sent photograph after page reload.
  Neither is acceptable as finished realtime media UX.

Corrective measures in this change:
- Register document/window capture-phase file drag and drop listeners while
  the actual room composer is mounted; prevent the browser's default file
  navigation, accept drops on message area/sidebar, overlay the entire
  conversation, and remove listeners on Stimulus disconnect.
- Preserve native text/link dragging (only intercept DataTransfer types Files).
- Browser test dispatches a file drop on #messages outside the form and
  asserts drop default was prevented and the file stored.
- Switch Chrome system acceptance from ActionCable's in-process async
  adapter to the **same Redis transport used locally**.
- Assert that room stream subscriptions have actually confirmed
  ([connected] attribute), rather than assuming DOM stream tags = live.
- All current per-user membership/authorization and private download checks
  remain in place.

Next: if Redis Chrome CI fails, diagnose runtime subscription logs rather
than making blanket claims. A pass confirms CI Redis conditions, NOT the
owner's exact Linux Mint browser; owner-local no-F5 test is still required.
Do not merge to main or deploy to Railway before acceptance.
