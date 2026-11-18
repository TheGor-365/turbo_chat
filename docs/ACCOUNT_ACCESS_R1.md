# R1 demo — account signup and password recovery policy

Updated 2026-11-12. Source policy: `app/services/demo_access_policy.rb`.
**R1 is a synthetic-data, owner-approved, controlled-access demonstration, not a general public SaaS.**

## Why these gates exist

At the time of this document, production SMTP, sender identity, recovery email delivery, email proof of ownership and HTTPS reset URLs have not been verified.
The existing Devise account model includes `registerable` and `recoverable`, but neither constitutes a working customer identity and recovery system. The configured Devise sender is still a placeholder.
Exposing email-reset forms with unverified delivery creates a broken account-recovery promise; uncontrolled signup could expose an unfinished public workspace to spam and unbounded storage/compute costs.

## Enforced policy

| Operation | Development / test | Production R1 |
| --- | --- | --- |
| Existing member sign-in / sign-out | Allowed | Allowed |
| Guest create-account link | Visible | Hidden |
| GET signup form / POST account creation | Allowed | 404 (blocked server-side) |
| Guest forgot-password link | Visible | Hidden |
| GET/POST email reset request | Allowed | 404 (blocked server-side) |
| GET/PUT password-reset-token form | Allowed | 404 (blocked server-side) |
| Authenticated profile edit / own-password change with current password | Existing behavior | Existing behavior |
| Private room / document permissions | Existing ACL | Existing ACL |

There is **no environment-variable bypass** for the production gates. Reopening signup or recovery requires a separately reviewed release with live acceptance.
This is not a substitute for email verification, tenant boundaries, rate-limiting validation, session security or an external security review.

## Controlled operator workflow (NOT EXECUTED)

A prospective tester requires owner approval, an independent isolated deployment, a named temporary access window, an individually issued synthetic-only identity and a unique single-user credential shared through an appropriate private channel.
Never publish a reusable demo login/password, use any owner-local Jack/Eric data, place credentials in Git or a shared Drive folder, or create production accounts from `db/seeds.rb`.
Record tester access and expiry/revocation separately without storing credentials in the public portfolio. No user should be admitted while a reliable forgotten-password route does not exist unless the lack of recovery and limited test purpose are clearly communicated and accepted.
No automatic or admin-password-reset console workflow is implemented in this iteration.

## Gates before open signup and email recovery

1. Operator chooses and verifies a real SMTP/email provider, sender domain authentication (SPF/DKIM/DMARC as applicable), safe server-side credentials and production host configuration.
2. Verify deliverability from the actual intended HTTPS domain, short-lived single-use reset links, expired/replayed token rejection, rate limiting, enumeration resistance and privacy-safe logs.
3. Design and test signup abuse controls, verified-account onboarding, controlled invites, account expiry/deletion, data retention and cost caps.
4. Validate production error/retry behavior for mail-provider downtime, anti-abuse controls and an alternate operator support process.
5. Require explicit owner approval to open the production policy; CI and externally verified acceptance for the release SHA.

## Current acceptance evidence

- Rails integration test simulates disabled production gates while retaining local forms and existing account profile access.
- Isolated production Docker CI must verify the blocked public endpoints on an ephemeral database.
- No actual SMTP delivery, invitation issuance, public users, external Railway project, paid resources, or HTTPS/WSS deployment is claimed.
