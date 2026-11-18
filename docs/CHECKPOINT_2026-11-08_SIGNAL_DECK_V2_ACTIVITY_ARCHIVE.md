# Signal Deck navigation + Activity archive V2 — 2026-11-08

## Owner evidence and design direction
- Local owner successfully fast-forwarded 5d7cbf3..b43348a and rebuilt Docker Compose; containers db/redis healthy, web recreated. Actual local repository is /home/gor/Рабочий стол/rails_projects/lite/turbo_chat (NOT ~/turbo_chat).
- Owner screenshots confirm Eric's private-group Leave matches public row; Eric leaves Project Circle and it disappears from his inbox; previous DM and public room persist; Activity lists authorized room history but looks like unstyled rectangular notification cards.
- Owner requested less duplication, one Public/Private toggle for rooms, unified row presentation, security-state icons and a substantial non-Bootstrap Activity/history redesign with search for text, image, documents, audio/video and emails, multiple filters and exact context navigation.

## Implemented on feature branch
- Left rail: Direct chat list remains separate from Rooms; Rooms has Public/Private toggle. Both views use the same room row, unread badge, preview, Leave action, and public/private SVG mark. One shared set of spacing/hover/focus rules, no private/public duplicate large sections. Invitations stay visible independent of toggle.
- Public view keeps joined rooms and discovery (no unauthorized message history); private view keeps new group creation and authorized groups. Group creation and discovery Join/Accept/Decline use compact icon-only controls with accessible names. Existing database and room authorization unchanged.
- Activity: search currently authorized room messages by exact text/filename with category chips (text/images/documents/audio/video/email mentions), room and time filters, bounded paginated results, media previews from authenticated attachment endpoints and exact deep links to message context. Unauthorized room IDs and former memberships cannot widen query. Search results are not notifications; event feed remains separate, with compact icon-based actions. Light/dark/mobile CSS, focus states and reduced motion covered.
- Email mentions are strings in chat messages; there is no Gmail/IMAP inbox integration and no claim to search external mail. Login emails are never indexed into public results.

## Gates
- No schema migrations, new paid APIs, production actions, main merge, deleting local db/schema.rb or storage. CI and owner-local visual acceptance required before calling UI final.
- Check latest exact HEAD green Rails/Chrome/security/Docker CI and verify 320/390/768/1440 appearance on the owner local machine.
