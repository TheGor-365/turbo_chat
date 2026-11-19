# Turbo Chat — baseline audit (2026-11-03)

Source: `main` at `b08ef33a9064454ef3770bd584c7735a151cd9be` (2023-02-07). Static GitHub source inspection only. No runtime tests, security exploit reproductions, or production deployment are asserted.

## Current stack

Ruby 3.1.2; Rails ~>7.0.4; PostgreSQL; Redis/Action Cable; Devise; Turbo/Stimulus; Bootstrap 5.2; esbuild; Active Storage; Pagy; Minitest. No confirmed RSpec or CI. README is a default template.

## Findings / risk register

| Severity | File | Finding | Acceptance gate |
| --- | --- | --- | --- |
| P0 | app/controllers/messages_controller.rb | No authentication and no room ACL prior to insert | Guest and nonmember request specs deny writes |
| P0 | app/controllers/rooms_controller.rb | Private room history exposed by direct find | Third-party GET returns forbidden and no data |
| P0 | app/controllers/users_controller.rb | DM endpoint lacks authentication; DM uniqueness depends on name | Auth tests, concurrent DM tests |
| P0 | app/models/room.rb | Disabled private-room broadcast guard | No private message content in global rooms stream |
| P0 | app/channels/apperance_channel.rb | Arbitrary client payload broadcast to global channel | Channel tests ensure no global relay |
| P0 | app/views/rooms/index.html.erb and app/models/message.rb | Turbo room stream needs per-member authorization review; direct stream tokens and access must be tested | Multi-client channel/system test |
| P1 | config/routes.rb | GET state-changing join/leave | POST/DELETE, CSRF specs |
| P1 | db/schema.rb | Missing unique composite indexes for membership; DM race possible | Migration + concurrency specs |
| P1 | config/environments/production.rb | Local transient file storage; SSL disabled | Private persistent storage + HTTPS smoke |
| P1 | app/models/user.rb | Global user broadcasts and status on any update; avatar callback | Privacy/callback tests |
| P1 | app/models/message.rb | Attachment validation missing, public-room membership not checked at model layer | Model/request/upload specs |
| P1 | app/helpers/rooms_helper.rb | Wildcard search unbounded; potential expensive query | Bound query length, results, escaping |
| P1 | test/controllers/rooms_controller_test.rb | Uses `rooms_index_url` despite resources route | Green test baseline |
| P2 | README.md | Template documentation | Reproducible setup and truthful product case |
| P2 | app/views/pages/home.html.erb | Minimal landing and copy typos | Responsive/a11y review |
| P2 | app/javascript/controllers/* | Client-side behavior and errors need browser regression | Two-browser e2e |
| P2 | Licensing/assets | No verified permission for default profile image and complete license | Ownership/licensing review |

## Product matrix (source-level)

| Capability | State |
| --- | --- |
| Devise authentication | Implemented; runtime unverified |
| Public rooms and search | Implemented; security/UX incomplete |
| Private DMs | Implemented; unauthorized reads must be blocked |
| Message creation and Turbo broadcasts | Implemented; authorization incomplete |
| Uploads | Implemented; validation and durable private storage absent |
| Unread counters, notifications, server presence | Missing |
| Profile settings and message edit/delete | Incomplete / unverified |
| Responsive polished SaaS UI | Missing |
| RSpec, CI, Docker, Railway demo | Missing / not confirmed |

## Execution order

1. Contain P0 authorization and global broadcast defects, add regression specs (current security branch is initial containment; NOT a verified release).
2. Establish green local/CI baseline, improve DB constraints, room scoping and authenticated Turbo subscription security.
3. Upgrade supported stack in incremental commits, retain Devise/Hotwire.
4. Complete chat flows, attachments, unread, notifications, presence.
5. Design system, responsive UX, browser QA.
6. Docker/CI/security scans/production storage, independent Railway project and staging release gate.
7. External two-client smoke, persistent upload/restart check; only then screenshot and portfolio exports.

### Additional requirements from audit

- Do not expose message content or email via global Turbo streams.
- Treat unauthorized message attachment downloads as a distinct endpoint/access-control case.
- Ensure private DM participants cannot be silently extended by name collision.
- Authenticate before making new data records; abort on duplicate membership and DB race.
- Avoid using public room subscription as proof of private authorization.
- In dev/test, intentionally simulate reconnect and duplicate form submission.
- Ensure orphan and stale attachment cleanup and predictable retention policy.

**Status:** first remediation proposed; NOT tested; no CI; not production-ready.
