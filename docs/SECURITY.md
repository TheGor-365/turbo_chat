# Security policy (work in progress)

This repository is an educational Rails/Hotwire SaaS showcase under active remediation and **must not be deployed publicly yet**.

## Reporting issues

Do not publish exploit payloads, private content, credentials, or personal data in public GitHub issues. Contact the maintainer privately via an established GitHub profile contact. No bug bounty is offered.

## Safeguards under implementation

- Devise session authentication on room/message/DM HTTP endpoints.
- Per-room access control and signed/private realtime broadcasts.
- Server-defined user identity; no client-trusted author ID.
- POST/DELETE state changes with Rails CSRF protection.
- Whitelisted attachment formats with file size/count validation.
- Per-user/IP rate limiting, safe storage, private download authorization, and database uniqueness.
- Dependency, Rails security, and JavaScript audits.
- Secret handling through deployment environment rather than committed credentials.

## Known limitations, 2026-11-03

Legacy runtime and dependencies; unverified private attachment download ACL; no verified WebSocket revocation upon room leave; unverified password reset SMTP; no confirmed security CI green; no public Railway deployment.

Do not enter real customer information or production credentials while testing this branch.
