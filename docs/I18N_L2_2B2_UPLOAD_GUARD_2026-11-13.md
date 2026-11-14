# L2.2b.2a — upload rejection text (2026-11-13)

- Only human-readable denial strings moved from `AttachmentUploadGuard` into four
  `ui.upload.*` catalogs. English values are byte-for-byte unchanged.
- Guards still reject signed blob IDs, oversized/mismatched files, malformed
  multipart input, incorrect MIME/signatures, too many attachments and empty files.
- Original filename is still bounded to 80 characters, stripped of control
  characters, and reduced to a basename. Response format/status are unchanged.
- Locale comes from existing controller request/cookie, not the content language;
  no AI or message translation is invoked.
- Added unit tests for localized guard output and integration test on avatar
  failure with account attributes unchanged.
- Do NOT modify existing accounts/files or SMTP settings for this check.

Next L2.2b.2b: localized Devise HTML email bodies and isolated mailer
rendering tests. The system does **not** have verified SMTP; never claim real
email delivery from an offline rendering test.
