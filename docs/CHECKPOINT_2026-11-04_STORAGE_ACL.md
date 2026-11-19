# Turbo Chat: P0 storage access checkpoint — 2026-11-04

## Implemented in feature branch

- Rails built-in Active Storage blob, disk and representation URLs disabled via `config.active_storage.draw_routes = false`.
- User-visible message attachment links use `chat_attachment_path` exclusively, with session authorization and current room access check.
- Avatar URL generation in message list, rooms, navigation, user card and registration views uses `user_avatar_path` instead of signed variant routes.
- New `UserAvatarsController` requires login, bounds size and MIME, returns no-store and nosniff.
- Request tests confirm old Active Storage routes do not resolve, avatar requires login, member obtains avatar bytes, missing owner returns 404, message attachments require room access.
- CI: https://github.com/TheGor-365/turbo_chat/actions/runs/41722165210 — PASS, 22 tests, 50 assertions, zero failures/errors/skips.

## Outstanding and risks

- Audit direct storage access at the provider layer for future Railway persistent storage; do not expose a bucket or filesystem through a public URL.
- Avatar visibility is currently scoped to **any authenticated account**, not exclusively shared-room contacts; establish product policy.
- Direct upload and pre-signed upload workflows have not been built or tested.
- File streaming currently uses in-memory `blob.download` with 5 MB model limit and needs further policy against historical oversized blobs.
- Perform real browser verification including image rendering, copied signed URLs, disconnect/reconnect and mobile views.
- Current legacy Ruby/Rails remains unchanged, and no production deployment is approved.

## Next P0 gate

Socket stream authorization and revocation on room leave, then atomic DM creation under concurrent requests. Draft PR only; main and Railway are untouched.
