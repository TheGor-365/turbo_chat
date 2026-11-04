# Checkpoint — first local screenshot and entry UX (2026-11-04)

## Observed on the user's Linux Mint
- Screenshot proves the home route renders in Chrome at `http://127.0.0.1:3000`.
- Local `git pull` succeeded over one-off HTTPS override and fast-forwarded to `da8457a`.
- `docker compose up -d --build` succeeded, PostgreSQL/Redis are healthy.
- `curl -I http://127.0.0.1:3000` returned **HTTP/1.1 200 OK**.
- `db/schema.rb` remains locally modified after Rails boot: **not inspected or reset**.

## Changes
- Replace misleading empty guest-visible `My messages` dropdown with a functional
  `Conversations` link available only after login.
- Create an honest portfolio-demo homepage with working CTA paths, development
  disclosure and actual feature descriptions (DM, realtime, private attachments).
- Add integration tests for guest and signed-in homepage CTA links and nav
  visibility; avoid implying production availability.
- This is a narrow first-screen fix, NOT the final responsive enterprise design.
  Signup form responsiveness and complete mobile visual QA remain open.

## Next owner acceptance
1. Update branch through HTTPS if SSH `git pull` remains unauthorized.
2. Refresh Docker Compose, open homepage at `http://127.0.0.1:3000`.
3. Create two separate local accounts in separate Chrome/incognito sessions.
   From Conversations click the other user's email to open a private DM;
   verify messages, edit/delete, and small allowed attachment.
Do not use production credentials, real client content or sensitive files.
