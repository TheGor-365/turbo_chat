# Turbo Chat security posture (release candidate, not audited production)

Updated 2026-11-12 for [Draft PR #2](https://github.com/TheGor-365/turbo_chat/pull/2).
**Do not publish this application as a live service or accept real customer data without the deployment and operational gates.**
This is a source-and-CI security statement, not a penetration test, compliance certification, service guarantee, or claim of end-to-end encryption.

## Reporting vulnerabilities

Do not include exploit details, credentials, private conversations, or customer files in public issues.
Contact the maintainer privately through the repository owner's GitHub profile. No bug bounty or guaranteed response time is offered.

## Controls implemented and exercised in tests

- Devise sessions, Rails CSRF protections, parameter validation and no client-supplied message-author identity.
- Room/member permissions for direct messages, groups, messaging, signed media reads and private AI document routes. H5 saved revisions are owner-only and re-check current room access, member consent, and cited source authors before viewing or exporting.
- Private Active Storage disk paths: files must be served through authorized application endpoints, not public blob directory listings.
- Anti-abuse/rate limits, Rails security headers/CSP, and automated code/dependency security audit as configured in CI.
- Explicit user actions for chat Send, private H5 Save and Export; consent and budgets for scoped provider access. No automatic approval or paid provider call during H5 export.

At commit `9f27d83`, [Rails/Chrome CI](https://github.com/TheGor-365/turbo_chat/actions/runs/43238063456),
[security audit](https://github.com/TheGor-365/turbo_chat/actions/runs/43238063275),
[Compose smoke](https://github.com/TheGor-365/turbo_chat/actions/runs/43238063334) and
[production-mode isolated smoke](https://github.com/TheGor-365/turbo_chat/actions/runs/43238063184) all passed.
The production-mode smoke used only an ephemeral CI database/Redis/private mount, demonstrated boot, guest auth, denied export and blob persistence through container replacement.

Additional [three-role authenticated production HTTP smoke at `86cb810`](https://github.com/TheGor-365/turbo_chat/actions/runs/43243637938) passed on disposable infrastructure: synthetic Devise logins with CSRF and cookie sessions, owner-only H5 export, non-member isolation, private chat attachment access and immediate H5 consent-revocation denial followed by explicitly restored consent. Passwords are generated at CI runtime, not preseeded or shared with a deployed instance. This does **not** verify real external TLS, WSS, or a production deployment.

## Unverified or incomplete operational controls

- No independently verified public Railway release, HTTPS/WSS browser acceptance, reconnect/revocation matrix or production traffic and abuse evaluation.
- No production database-plus-media encrypted offsite backup with independent restore, measured RPO/RTO or alerts.
- No live production SMTP/password reset acceptance; Devise currently has a placeholder mailer sender. This is **not** evidence of functional outbound account recovery.
- No completed external security review, production privacy/retention operations, incident response, or certified E2EE.
- Multi-tenant paid operations, public signup abuse prevention at production scale, provider billing and customer data handling are outside R1 approval.

Do not place user credentials, keys, private screenshots, customer text or local test messages into GitHub, shared Drive or public demo seeds. For deployment blockers and owner approval see [DEPLOY_RAILWAY.md](DEPLOY_RAILWAY.md) and [RELEASE_CHECKLIST.md](RELEASE_CHECKLIST.md).
