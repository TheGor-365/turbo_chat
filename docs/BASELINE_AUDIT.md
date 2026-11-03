# Turbo Chat — source baseline audit

Date: 2026-11-03. Audited commit: `b08ef33a9064454ef3770bd584c7735a151cd9be` (main, 2023-02-07).
Method: GitHub API source/tree and configuration inspection, NOT a successful runtime/penetration test.

## Inventory
- Rails 7.0.x / Ruby 3.1.2, PostgreSQL, Redis Action Cable, Devise, Turbo/Stimulus, Bootstrap 5.2, esbuild and Sass; no existing GitHub Actions workflow, Dockerfile, compose file, RSpec suite, or Railway production configuration in tracked tree.
- Models: User, Room, Message, Participant (DM membership), Joinable (public room membership).
- Controllers: Rooms#index/show/create/search/join/leave; Messages#create; Users#show.
- Realtime: room-specific Turbo Streams, a global `rooms` stream, a global `user_status` stream and an `ApperanceChannel`.
- Routes allow GET mutations `/rooms/join/:id` and `/rooms/leave/:id`; `users#show` also creates a room from a GET.
- Storage: Active Storage local disk in production; no persistence policy.
- Tests: old Minitest fixtures and stubs. `rooms_index_url` in rooms controller test does not match resource route. Fixtures use two users without unique emails and two rooms sharing a name; no verified green suite.

## Critical findings (static proof, runtime exploit NOT VERIFIED)
| ID | Priority | Path | Finding and impact | Acceptance |
|---|---|---|---|---|
| SEC-01 | P0 | app/controllers/messages_controller.rb | No auth or membership check before create; current_user can be nil | guest and nonmember cannot create; signed-in permitted member can |
| SEC-02 | P0 | app/controllers/rooms_controller.rb | `show` loads arbitrary Room and its messages | nonmember/private third party forbidden; no content revealed |
| SEC-03 | P0 | app/controllers/users_controller.rb | Missing auth and non-idempotent GET DM creation | authenticated only; pair uniqueness, concurrent safety |
| SEC-04 | P0 | app/models/room.rb | Global `rooms` stream broadcast does not filter private rooms | no private content or metadata in global stream |
| SEC-05 | P0 | app/channels/apperance_channel.rb | Unrestricted `receive(data)` forwards arbitrary payload to global channel; JS subscriber spells channel differently | arbitrary client payload never rebroadcast |
| SEC-06 | P0 | app/controllers/rooms_controller.rb | Room creation has no role check; UI-only admin gate | non-admin POST denied |
| SEC-07 | P1 | config/routes.rb | GET mutations for membership; private rooms can be joined without explicit policy | POST/DELETE only and idempotent membership |
| SEC-08 | P1 | app/models/{room,user,message}.rb | callback broadcasts and local attachments need information-flow and lifecycle review | scoped streams and protected download URLs |
| SEC-09 | P1 | db/schema.rb | no composite unique membership indexes, no DB uniqueness on room name | preflight duplicates then unique constraints |
| SEC-10 | P1 | config/environments/production.rb | local attachments, force_ssl off, no verified persistent storage | private persistent storage, HTTPS and redeploy test |
| SEC-11 | P1 | config/database.yml,config/cable.yml | hardcoded local PostgreSQL and localhost Redis fallbacks in production | mandatory DATABASE_URL and REDIS_URL; secrets in env |
| SEC-12 | P1 | app/views/messages/_message.html.erb | signed Active Storage URLs without per-request membership enforcement | unrelated user cannot download even with guessed/copied URL |
| SEC-13 | P1 | app/models/user.rb | default avatar `after_commit` on create/update can attach during update callback | deterministic one-time default without recursion |
| SEC-14 | P1 | app/javascript/channels/appaerance_channel.js | 5 second idle timeout, typo `onffline`, incorrect cleanup; online is not real presence | server-derived heartbeat/expiry and multi-tab handling |
| QA-01 | P1 | app/views/rooms/index.html+turbo_frame.erb | `@pager` used vs controller `@pagy` | paging does not raise and is stable |
| QA-02 | P1 | app/controllers/messages_controller.rb | attachments read outside permitted `message` params; form submits nested attachments | validated upload saved and rendered |
| QA-03 | P1 | app/controllers/users_controller.rb | sorts ActiveRecord User objects instead of IDs, may raise | deterministic DM name and idempotence |
| QA-04 | P1 | app/views/layouts/_nav.html.erb | empty My messages dropdown; placeholder links | no dead controls |
| QA-05 | P1 | app/helpers/rooms_helper.rb | unrestricted wildcard/length input; repeated membership query | bounded escaped search, indexes, pagination |
| QA-06 | P1 | test/fixtures/*.yml | incomplete duplicate/invalid fixtures | reproducible valid fixtures and passing tests |
| OPS-01 | P1 | entire repo | missing CI, Docker, health endpoint, env template, release runbook | clean runner and container checks |
| UX-01 | P2 | app/views, app/assets | nonresponsive sidebar and dark-only incomplete marketing screen | responsive QA at 320/390/768/1440 |

## Function matrix
| Capability | Baseline |
|---|---|
| Devise signup/login | present in source; end-to-end NOT VERIFIED |
| Public room list/search | implemented; security/QA NOT VERIFIED |
| Create/join/leave | implemented, role/HTTP safety broken |
| DM | implemented with insecure GET and race risk |
| Message send/realtime | implemented; auth bug, delivery NOT VERIFIED |
| Attachments | implemented; private download and limits missing |
| Pagination | present; broken variable path suspected |
| Edit/delete own message | missing |
| Unread/read receipts | missing |
| Reliable presence | broken |
| Notification/empty states | missing/incomplete |
| Production deployment & screenshots | not verified |

## Constraints and decisions
Preserve the existing repository, Rails server rendering, existing domain records and migrations. Do not deploy until all P0 and critical P1 gates pass. Do not delete existing user data. Do not invent runtime results or portfolio statistics. P0 security first; no untested mass framework upgrade.

## Additional gaps beyond the master brief
Data migration preflight for existing duplicate room names and memberships; recovery from partially-created private rooms; multi-tab presence races; idempotency keys for retry; bounded search input; files served via membership-checked endpoints (signed URL alone is not an authorization model); rate limiting over WebSocket and HTTP; valid fixture seeding; missing controller response formats; generated assets and real browser QA; account data erasure/retention; UX accessibility and error states.

## Baseline validation status
GitHub source inspected: YES. Runtime boot, `rails test`, RSpec, code scanners, JS build, multi-browser, external URL, storage persistence, and restore test: NOT RUN/NOT VERIFIED. This file documents review, not a security certification.
