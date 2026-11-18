# CHECKPOINT — Live room-scoped message search (2026-11-05)

## Owner evidence and requested UX
- Existing local search `nice` returned a hit only after Search click; user confirmed it finds the right message but called the UX primitive.
- Explicit request: **no mandatory Search click**, responsive matching as the query is typed, either reliable exact-message navigation or a results page with a quick return. Authorized choice: debounced inline results overlay with linked message navigation.
- Earlier owner-local DM typing acceptance: PASS on local branch `65f927f`. No need to repeat typing acceptance.

## Delivered in Draft PR #2
- `message_search_controller.js`: debounce 500ms, no request for queries below 2 chars, cancel stale requests, bound latest-result rendering, clear/Escape, no editor reset. Uses authenticated room-scoped GET, no global search, no persisted typed drafts.
- Search form has no Search submit button; async results appear beneath field, scroll independently over chat history (not pushing the composer).
- Result rows: whole-card navigation, contextual snippet, safely escaped server-side `<mark>` matching, author/time, page controls for more than 15 hits, explicit Close.
- Clicking a hit navigates to `/rooms/:id?focus=:message_id#message_:id`. On load, scroll controller prioritizes the exact message anchor and existing banner offers **Return to latest messages**.
- Historical focus does not acknowledge newer unread messages (preceding fix), and all results remain bound to current room membership with no cross-room lookup.
- Browser tests cover result-on-input with no click, highlight, historical open/return, query changes/clearing and composer draft preservation. Integration tests cover membership, wildcards, escaped HTML, pagination, and query-length validation.
- An old assertion used raw HTML substring `secret-room-query-2026`; highlights insert a tag inside the text, so this was corrected to inspect rendered text and `<mark>`.

## Safety / status
- Branch: `feat/security-baseline-2026-11-03`, PR: https://github.com/TheGor-365/turbo_chat/pull/2 . **Do not merge or deploy without approval.**
- No schema migrations, local filesystem writes, existing Railway changes, paid API calls, secrets or external email.
- Owner's `db/schema.rb` is locally modified; preserved backup at `~/turbo_chat_schema_backup_2026-11-05.patch` per owner terminal output.
- **CI conclusion and owner-local browser acceptance for this new dynamic search commit are pending** at checkpoint creation; check the HEAD workflow jobs before claiming success.
- Local update when checks pass: `git pull --ff-only` then `yarn build && yarn build:css && docker compose restart web`. If pull conflicts with user modifications, stop and inspect; never reset their worktree.

## Next Gate 1
1. Validate live search from two real browser sessions for multiple matching messages and jump/return without wiping an unsent message during searching.
2. Validate All/Unread after new message + read acknowledgment in second tab (including historical jump).
3. Continue reliable real presence with TTL and per-user in-app notifications, without changing legacy user status to false online.
