# P1 local direct conversations & nonempty UX (2026-11-04)

User-local verification:
- Demo account `demo1@example.com` created and logged in, homepage and
  account settings render, `/rooms` opened successfully.
- Single-account Users list and first-room list were blank in screenshot.
- Existing account edit showed unbounded full-size portrait; corrected separately.
- Do not claim two-account DM or WebSocket verified on user's machine yet.

Core product completion:
- GET `/rooms` loads up to 50 private rooms where logged-in user has a
  Participant record; excludes all unrelated private rooms.
- Show the peer's email, not technical `private_123_456` name, in
  both sidebar and chat title.
- GET `/rooms/:id` is still guarded via Room#accessible_to?.
- Empty states for no other accounts, no DMs, no public rooms and no
  selected chat. These are interim functional affordances, not the
  approved premium design.
- Scope public joined room listing, limit sidebar queries and include
  peer users to reduce N+1. Keep legacy room search.
- Tests for private room persistence, outsider confidentiality and
  authorized room heading plus POST creation navigation.

Owner acceptance: create a second local test account in Chrome incognito;
original account should list it. Click counterpart email; check that both
users can open the DM and see messages, then verify reconnect/reload,
edit, delete and allowed attachments. No new demo account auto-seeding.
