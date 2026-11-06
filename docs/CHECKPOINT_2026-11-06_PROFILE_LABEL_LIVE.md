# Turbo Chat — live display label handoff (2026-11-06)

## Local evidence and motivation
Owner screenshots confirm that the profile page is scrollable, its links are accessible, and two local users named **Gor** and **Eric** have their labels saved. Previously opened conversations required a browser reload before those names were shown.

## Implementation on Draft PR #2
- Existing `User#chat_label` remains the single display identity; no email is rendered as a peer label.
- A `ProfileLabelsChannel` subscribes only via the authenticated Action Cable connection. Its streams are account-scoped, not globally broadcast. Broadcast recipients are the account owner and other members of its currently joined private conversations.
- The event transmits only `user_id` and the validated `label`. A small authorized reconnect snapshot updates missed events. The inbox receives only a privacy-safe invalidation signal and fetches its own ACL-checked snapshot.
- `profile-labels` Stimulus uses `textContent` and updates only explicitly identified DOM labels, initials, reply accessibility text, and audio/video accessible labels. No `innerHTML`, no client-selected stream target, no private chat body in events.
- Browser acceptance covers two open chat sessions plus a settings session. Channel tests cover authorization, no stranger broadcast, invalid inputs, and identity masking.

## Scope and remaining gates
- This slice concerns user display names, not avatars or live editing of every rich historical message artifact. Public-room users without an existing direct conversation are not granted a profile event stream; their labels reconcile on navigation.
- Does not touch local DB schema, user uploaded media, Railway, production settings, or `main`.
- Gate 3 premium design remains separate and requires the owner's choice among visual concepts. Validate this change in CI and on the two local demo accounts before recording it as locally accepted.
