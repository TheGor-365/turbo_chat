# 2026-11-04 — P0 room creation ACL and safe DM initiation

- User screenshot confirms updated developer homepage at 127.0.0.1:3000;
  local `git pull` through one-time HTTPS and Docker rebuild succeeded.
- P0: create public rooms now requires server-side `current_user.admin?`,
  not just a hidden input.
- P0: personal conversation creation moved from GET `/user/:id`
  (database mutation on navigation) to CSRF-protected POST
  `/user/:id/conversation` followed by 303 redirect to the room.
- Per-user direct room creation rate-limited to 10/min.
- User list avatar/email now use POST buttons, preserving simple
  one-click start flow. No seeded admins introduced.
- Tests cover denial for regular users, admin success, guest denial,
  GET no-create, idempotence, third-party room isolation, self-action.
- Full UI redesign remains deferred until P0 and product-function gates;
  requirements captured in `docs/UI_UX_DESIGN_BRIEF_2026-11-04.md`.
- Pending: actual user signup and two-browser DM screenshot, real Ruby CI,
  mobile UX, missing SMTP, product design concept approval.
