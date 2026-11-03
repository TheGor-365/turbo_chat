# Security status (draft, not a certification)

2026-11-03: source audit discovered unauthorized room access, message writes, admin-only UI without server enforcement, GET mutations, global private broadcast and unsafe attachments.

An isolated feature branch now contains mitigations. **Do not deploy publicly** until security acceptance tests are green, direct Active Storage routes are reviewed, file MIME sniffing/limit enforcement is verified, rate limits and WebSocket protections are in place, supported runtime versions are pinned, and CI/browser QA is complete.

Never commit authentication credentials, demo passwords, customer records or private data. Report vulnerabilities privately through the repository owner's trusted contact channel rather than opening a public issue with secret details.
