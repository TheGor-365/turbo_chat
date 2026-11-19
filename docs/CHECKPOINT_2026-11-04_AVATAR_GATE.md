# P0 checkpoint — avatar multipart gate

Date: 2026-11-04. Branch: `feat/security-baseline-2026-11-03` (draft PR #2).

## Change
- Reuse the message upload guard's byte-header/MIME validation for avatar forms, without altering permitted message formats.
- Devise sign-up and account update reject non-multipart avatar values, signed Active Storage blob IDs, excessive bytes, disallowed media types, and mismatched header/MIME before database persistence.
- Valid JPEG/PNG/WebP multipart avatars remain supported; avatar is optional.
- Six HTTP regression scenarios include valid registration and profile update, HTML spoofing, signed-blob bypass, over-limit payload, and unchanged account attributes on rejection.

## Limits and next release gates
- A first 4096-byte signature is **not** full image decoding, AV scanning, zip-bomb protection or malware scanning. Image processing and private object storage remain separate P0 gates.
- Model-level attachment through non-HTTP/internal code paths is *not* protected by this controller guard.
- Public Active Storage routes remain disabled; authenticated custom routes still need streaming and object-store backup QA.
- No production deployment, `main` merge, S3 provisioning, or costly resources approved by this checkpoint.
