# 2026-11-04 — Multipart attachment byte gate

**Scope:** existing draft PR #2, not `main`. No Railway resources created or changed.

## New guard (SHA cabdb67c2dffcb1e5d4c42e0fefe65360f61c2d9)

- `app/services/attachment_upload_guard.rb`: before a message is persisted, normal multipart uploads are bounded by file count and size, validated against an allowlist, checked using Marcel MIME detection and independent file signatures for JPEG, PNG, WebP, PDF and plain text.
- `app/controllers/messages_controller.rb`: inaccessible rooms are rejected before inspecting attachments; unsafe uploads do not persist a message. Turbo submissions return HTTP 422, HTML submissions redirect with a specific validation alert.
- `test/controllers/messages_controller_test.rb`: positive UTF-8 text upload, spoofed HTML-as-PNG rejection, rejection of signed blob ID that bypasses multipart inspection.
- `test/fixtures/files/`: sample .txt and malicious HTML test fixtures.

## Evidence

- CI `Baseline Rails CI`: https://github.com/TheGor-365/turbo_chat/actions/runs/41743569824 — **SUCCESS**.
  - 54 Rails test runs / 218 assertions / 0 failures / 0 errors / **2 intentional Redis-specific skips** in generic test mode.
  - Dedicated Redis tests: 2 / 6 / 0 failures.
  - Three real Chrome browser tests: 3 / 37 / 0 failures.
  - PostgreSQL preparation/migrations and frontend assets passed.
- `Security audit`: https://github.com/TheGor-365/turbo_chat/actions/runs/41743569889 — **SUCCESS**.

## Limitations / next release gates

**Not a complete file-upload security acceptance.** The guard covers ordinary `multipart/form-data` uploads via `MessagesController#create`, not arbitrary model-level attachments or a future direct-upload API. Only the first 4096 bytes and supported file magic are inspected, not complete decoding or antivirus. Avatar upload retains a separate metadata validation path. The authenticated attachment controller still downloads whole permitted objects into memory; review streaming, object-storage durability, content sniffing, request ingress/body limits and malformed-file handling before a public demo.

Remaining blocks: browser and multi-worker Redis ActionCable under production-like setup; persistent private storage and backup; Rails 8 defaults review; RSpec quality stack; comprehensive mobile UI; demo abuse controls, health, Docker, isolated Railway staging with billing approval, final QA and screenshots.

**Decision:** keep PR #2 in DRAFT; no merge into `main`, no public deploy, no unverified commercial claims.
