# Testing status — 2026-11-03

Source snapshot: `b08ef33`; changes live only on feature branch.

- Existing project has Minitest, not RSpec. Minitest request/model coverage added for authentication, room authorization, message sending, DM idempotence and private attachment download.
- GitHub Actions baseline workflow runs Ruby 3.1.2, PostgreSQL 16, Node 24, yarn assets and Rails tests. This is temporary compatibility CI, **not** the final supported runtime.
- CI status, browser system tests, RSpec, RuboCop, Brakeman, dependency security scan, full Docker and production checks are **NOT VERIFIED** until actual green job logs.
- All negative assertions are expected behavior; presence of a test file is not evidence it passed.
- Before any Rails upgrade: record baseline failures and lockfile/distro incompatibilities, repair incrementally, and keep Minitest until RSpec coverage proves equivalent.
