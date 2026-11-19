# Gate 1 — Stable historical search navigation (2026-11-05)

## Owner acceptance and defect evidence
- Owner fast-forwarded their Linux Mint worktree to `67cfba2`, built JS/CSS and restarted the local Docker web service. Search-as-you-type works, highlighted result list works, and clicking a result opens `?focus=<message-id>`.
- Three owner screenshots establish a **navigation defect**, not completion: URLs contained `#message_8` and `#message_2`. After jumping, the browser scrolled beyond the chat's own scroll pane, clipping the page header and making the history-return banner hard to reach. Owner also requested smooth scroll and a simple exit.
- Current code confirmed two underlying scrolling mechanisms: link URLs included `anchor: dom_id(message)` and `scroll_controller.js` invoked `target.scrollIntoView({block:"center"})`. Both can scroll ancestors / the whole page.
- Owner requested comparison with WhatsApp/Telegram. Official WhatsApp guidance: select a result to open the message inside chat; Telegram provides compact search results and jumps. A WhatsApp 2026 beta report describes contextual scroll-to-latest affordances. Sources:
  - https://faq.whatsapp.com/1131773267485499/
  - https://t.me/s/TelegramTips/180
  - https://wabetainfo.com/whatsapp-is-working-on-a-chat-search-shortcut-for-ios/

## Scoped implementation in existing Draft PR #2
- Search-result links now use `/rooms/:id?focus=N` **without any hash**. Existing server-side authorization still verifies membership and resolves the hit only inside the current room.
- Move Stimulus scroll-controller scope to `#single_room`; target `#messages` as the **only scroll container**. Compute bounded target offset using the scroller and message bounding rects and `scrollTo({behavior:"smooth"})`, respecting `prefers-reduced-motion`.
- Highlight `.message-focused` for explicit visual context. Normal live-chat follow-bottom remains conditional; when the reader scrolls up, show a floating, smooth `Latest messages` shortcut.
- A visible, high-contrast **Viewing an older message** banner sits above the scroller, with **Return to latest messages** action. The floating latest shortcut also exits historical view. Escape returns to latest when an input/textarea is not focused.
- Legacy deep links with `#message_N` are stripped on focused page initialization; browser-level scroll is reset to the top before chat-scoped positioning.
- No draft persistence, no database migrations, no ACL changes, no existing Railway modifications, no merge to main.
- New integration assertions require fragment-free result URLs, scoped focus ID, and exit controls. System tests cover focus highlight, header not disappearing, browser window scrollY staying 0, inner scroll movement, floating latest shortcut and Escape.

## Acceptance boundaries
- Latest code at time of this checkpoint: commits beginning `52bc152` through `ca81b49` on `feat/security-baseline-2026-11-03`.
- **Do not claim PASS until GitHub Actions conclude on the final HEAD and owner validates the Linux Mint Chrome behavior**.
- Local `db/schema.rb` remains user-modified. Owner previously backed it up at `~/turbo_chat_schema_backup_2026-11-05.patch`. Never `git reset --hard` or erase that file.
- Next owner actions after green CI: `git pull --ff-only`; `yarn build && yarn build:css && docker compose restart web`; search `nice` and `Hey`, click result, inspect stable header, smooth in-pane scroll and easy return.
- Gate 1 after acceptance: validate All/Unread across two browsers and then presence TTL/notifications. No launch or production deployment authorization.
