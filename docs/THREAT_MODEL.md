# Threat model — Turbo Chat / Relay Workspace (draft)

Baseline: main `b08ef33` on 2026-11-03. Source inspection only; no exploit/pentest verified.

## Assets and trust boundaries
- Private conversations, message history, attachments, user emails/status, session cookies, admin-only room creation, database/Redis and object storage credentials.
- Boundaries: anonymous browser → Devise session → Rails controller → SQL/Active Storage; browser → Action Cable WSS → signed Turbo stream name → broadcast; private object store → authorized download response.
- Roles: anonymous, authenticated nonmember, public-room member, DM participant, admin; demo operator is not a superuser bypass.

| Threat | Attack | Mitigation | Test / status |
|---|---|---|---|
| IDOR history | GET another DM room ID | scope room lookup to membership and fail closed | outsider GET 404; not implemented in baseline |
| Forged message | POST room_id of another DM | user auth + membership before build | 302 guest, outsider 404; not implemented in baseline |
| Broadcast leak | private room last-message to global `rooms` stream | skip private broadcasts and avoid displaying DM metadata globally | check stream payload (pending) |
| WS injection | arbitrary `receive` client event rebroadcast | remove/disable arbitrary receive | channel spec (pending) |
| Unauthorized room | POST rooms as nonadmin | server-side role check | request spec (pending) |
| CSRF/GET mutation | cross-origin GET join/leave or DM creation | POST/DELETE membership, GET read only | routing/request spec (pending) |
| Blob URL sharing | signed blob URL not tied to current room member | authenticated attachment endpoint, disable unguarded direct routes | outsider attachment spec (pending) |
| Mass upload / malicious file | oversized/polyglot user attachment | server-side content inspection, allowlist and limits | invalid type/size specs (pending) |
| Duplicate DM | two concurrent DM creation requests | deterministic key + unique DB index + conflict handling | parallel spec (pending) |
| Spam / resource exhaustion | signup, search, message flood, oversized WS | rate limits and bounds; metrics | 429 specs (pending) |
| Session/HTTPS | insecure cookie/host, redirect | SSL, approved hosts, CSP and CSRF | production smoke (pending) |
| Leaked credentials | repository, CI or logs include secret | env-only, filter params, history scan | scanner, history audit (pending) |

## Nonclaims
No end-to-end encryption. No SOC2, paid customers, production SLA, incident response certification or verified backups. Signed Turbo Stream names are not a substitute for authorization on HTTP page and storage endpoints.
