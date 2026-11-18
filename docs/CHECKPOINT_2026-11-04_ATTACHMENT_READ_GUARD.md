# P0 checkpoint — protected reads for legacy message blobs

Date: 2026-11-04. Draft PR #2.

The custom authenticated attachment controller additionally rejects
unsupported MIME types and objects larger than Message::MAX_ATTACHMENT_BYTES
before downloading or rendering them. This is important for legacy data and
direct/internal Active Storage writes that bypass the HTTP upload guard.

Two integration regressions create an internal SVG blob and an oversized plain
text blob directly in Active Storage, then assert that a signed-in room member
still receives HTTP 404. Existing tests continue to cover authorized member
reads, nonmember denial, and revocation after leaving a room.

This does not implement streaming, transcoding, object-store encryption,
malware scanning, or independent backup; those release blockers remain open.
