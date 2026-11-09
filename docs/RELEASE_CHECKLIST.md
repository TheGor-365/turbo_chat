# Turbo Chat release gates

- [ ] Supported Ruby/Rails/Node and locked dependencies
- [ ] PostgreSQL schema migrated with uniqueness constraints
- [ ] All request/model/channel/system tests green in CI
- [ ] Unauthorized HTTP read/write and forged IDs denied
- [ ] Nonmember cannot subscribe to or retrieve private DM streams/blobs
- [ ] Real message delivery in two browsers without reload
- [ ] Attachment upload type/count/bytes and download ACL verified
- [ ] Unread/read, presence, notifications and settings verified
- [ ] Zero known critical Brakeman/dependency findings
- [ ] Docker build and clean compose start green
- [ ] Railway new isolated project, budget approval and backups reviewed
- [ ] External HTTPS, websocket reconnect, fresh client and restart tested
- [ ] Homepage GET does not mutate presence; actionable signed-in Home and honest guest entry
- [ ] Original favicon/touch app icons and safe styled 404/422/500 responses, verified status codes
- [ ] Account, Activity filters and dropdowns owner-accepted; Devise/ACL and keyboard/mobile behavior preserved
- [ ] Desktop/mobile and accessibility screenshots reviewed
- [ ] Source screenshots, facts, marketing exports and RU/EN case grounded in live SHA
- [ ] Drive readback and local ZIP checksum confirmed
- [ ] Owner authorizes merge to main separately

**Current state: NOT RELEASE READY.** No unchecked item is considered done.
