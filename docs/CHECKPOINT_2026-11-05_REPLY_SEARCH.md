# Turbo Chat — Reply hardening + room-scoped search, 2026-11-05

## Verified baseline from owner
- `CreateMessageReactions` and `CreateConversationReadStates` migrations ran successfully on the existing local Docker PostgreSQL.
- Owner-local screenshots show 👍 reaction visible on both sides and `Live · WebSocket connected` on both browsers.
- User reports Reply not behaving as expected; **no screenshot showing the state immediately after pressing Reply**. Prior browser tests for text and attachment-only replies were green, so root cause on the user's machine is not yet proven.

## Changes in this branch
- Composer Reply listener is delegated to its owning `#single_room`, not a document-global Stimulus action. Covers messages appended/replaced after page load. Existing draft and attachments survive replying; successful sends clear Reply.
- Add read-only, authorized `GET /rooms/:room_id/messages/search?q=` with case-insensitive PostgreSQL `ILIKE`, escaped wildcard characters, 2–100 character search terms, 15 results/page, rate limiting, and `private, no-store`.
- Only message bodies are searched; private attachments, filenames and unrelated rooms are not indexed or exported.
- Search result opens the actual matching message with `/rooms/:id?focus=:message_id#message_:id` and a return-to-latest link, even if it was older than the latest 10 entries.
- Integration tests for guest, IDOR, unjoined rooms, LIKE wildcard escaping, pagination and deep history. Chrome test for live-appended Reply plus search navigation.
- No data migration; no `db/schema.rb` changes; no new services, API keys, storage, billable AI, merge to `main`, or Railway modification.

## Owner next after green CI
- `git status --short --branch`, `git pull --ff-only`, `docker compose exec web yarn build`, `docker compose restart web` if needed to ensure the updated JavaScript bundle is served.
- Two browsers: Reply to incoming dynamically delivered message; verify preview, unchanged draft, send and quoted reply in other session. Search an older message by a unique term and open it.
- Audio hardware hiss remains deferred to final pre-release QA. Media players showing 0:00 still need actual playback validation.
