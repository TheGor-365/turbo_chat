# ADR 0001: Per-member Turbo streams instead of a reusable room-wide stream

Date: 2026-11-03
Status: Proposed / pending runtime acceptance

## Context

The source application signed and rendered a room-wide Turbo Stream token to anyone who opened a room. After leaving a public room or removal from a private room, a previously copied signed stream token could remain usable for future room broadcasts. HTTP authorization alone does not revoke an already issued stream.

## Decision

Use a separate signed stream name per (room, authorized user). Messages broadcast only to the current membership list. Leaving/removing a user stops future message delivery to their previously issued stream name even while the WebSocket remains connected. The room still requires HTTP authorization before rendering a token.

## Trade-offs

Broadcast fan-out grows linearly with membership. This is appropriate for small teams and demo workspaces but must be load tested before large rooms. Message history and attachment endpoints require independent authorization. This is not end-to-end encryption or complete token revocation.

## Acceptance

- Two members each receive the message once without reload.
- Guest and nonmember cannot read the conversation or obtain a token.
- After leaving, a previously subscribed socket sees no subsequent messages.
- Private messages are never sent on a global stream.
- Reconnect and duplicate message handling are tested in a browser.
