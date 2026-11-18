# P0 checkpoint — remove default known-password admin seeds

Date: 2026-11-04. The original development seed file created admin
accounts with public, hard-coded credentials and arbitrary sample rooms when
Rails db:prepare seeded a fresh database.

The default seed file is now intentionally non-mutating, including in
development/test/production. New local users register through the UI. This
prevents accidental privileged sample accounts at a future staging deploy.

No existing records were deleted and existing accounts were not touched.
Anyone with an **old** local database must inspect whether those historical
accounts exist and change credentials or discard only that isolated local demo
database after explicit consent. This change does not automatically revoke
or rotate previously created passwords.

Regression: loading db/seeds.rb must not change user/room counts or create
the two previous known admin emails.
