# Markdown upload end-to-end CI repair (2026-11-04)

Initial patch `6f2b119` accepted `.md` drops on the JavaScript side
and passed service-level UTF-8 checks, but the Chrome system test caught
a 422 during message persistence. Root cause: Active Storage can store
Markdown as `text/markdown` even when the browser sends `text/plain`.
Message model's allowed blob content types and the private-download
controller's allowlist did not include this resolved content type.

Repair:
- Keep multipart upload guard's strict UTF-8 check, size limit, no-NUL
  and no HTML/XML start; do NOT accept arbitrary file extensions.
- Allow `text/markdown` on persisted blobs as an inert text-only file,
  and use the existing attachment endpoint's private authentication,
  no-sniff and attachment Content-Disposition.
- Regression test entire multipart -> saved blob -> private download
  with `upload_note.md` fixture.
- Chrome test also requires actual message persistence after dropping
  a Markdown file with an unknown browser MIME type.
- No running environment or client data modified until owner fetches.
