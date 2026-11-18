# Turbo Chat threat model (initial, 2026-11-03)

**Status:** draft, code review only; no penetration test or production certification.

## Assets and trust boundaries

- User sessions, account identities, room membership, private conversation bodies, presence, and uploaded files are protected assets.
- Browser-controlled params and WebSocket messages are untrusted. Authenticated user identity must originate from Devise/Warden, never client-submitted user IDs.
- Boundary A: unauthenticated browser -> HTTP controllers.
- Boundary B: authenticated member -> room/message scoping and private DM.
- Boundary C: authenticated browser -> Action Cable channel / signed Turbo stream token.
- Boundary D: attachment metadata -> Active Storage blob and download.
- Boundary E: Railway app -> PostgreSQL, Cable backend, and persistent blob storage.

## Attack cases and required evidence

| Threat | Mitigation design | Test / evidence | Current result |
| --- | --- | --- | --- |
| Guest POSTs message | authenticate_user! in controller | guest POST integration test | Code added, test not yet verified |
| Member reads arbitrary private DM ID | Room#accessible_to? in show | third-party GET integration spec | Code added, test not yet verified |
| User impersonates another message author | assign current_user server-side | forged user_id request | Missing test |
| Nonmember writes to public room | server room membership check in controller/model | nonmember POST integration test | Code added, test not yet verified |
| Private message advertised globally | private-room guard on room activity broadcast | 2-subscriber test | Code added, test missing |
| Private Turbo stream token reused after member removal | subscription authorization/revocation design | channel/2-client test | Not fixed |
| Client injects untrusted appearance payload | no global client receive relay | Action Cable test | Code added, test missing |
| Attachment size/MIME bypass | model-level validation, download ACL | crafted upload, direct URL tests | Initial validation added; download ACL unverified |
| Duplicate private rooms from concurrent requests | DB unique constraints + transaction retry | 2-thread test | Not fixed |
| GET causes join/leave | POST/DELETE + CSRF | GET method test | Code added, test unverified |
| Long/wildcard room search overload | bounds + query escaping + rate limits | input abuse spec | Not fixed |
| User email/message exposed in logs | filters, exception and audit review | log review | Not verified |
| Denial of service/message spam | per-IP/account limits | 429 tests | Not fixed |

## Release rule

Any P0/P1 open authorization or storage issue blocks public demo. GitHub Actions success alone never proves runtime authorization, browser isolation, secure storage, or complete deployment.
