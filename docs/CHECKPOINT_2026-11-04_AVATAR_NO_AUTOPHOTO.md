# Avatar and account-form preview correction — 2026-11-04

Evidence from user's own browser: account `demo1@example.com` registered
successfully and could visit settings and conversations. Account settings
rendered the original avatar with unrestricted intrinsic width/height,
requiring a long page scroll. The conversations page has no empty states.

Code inspection: `User.after_commit :add_default_avatar` attached the same
bundled `default_profile.jpg` to every account. This leaks a potentially
identifying portrait to unrelated demo accounts and incurs redundant blobs.
For **new accounts only**, stop that callback; existing uploaded/auto-attached
avatar blobs are **not removed or modified**.

- Profile edit preview: 96x96 crop with accessibility text; responsive
  account form width; neutral letter fallback where there is no attachment.
- Registration form: responsive instead of fixed `col-6` width.
- Room sidebar users/self: neutral initials when no avatar is attached,
  avoiding broken private avatar URLs.
- Tests for new account without default portrait and sidebar render.

Remaining: owner's review of licensing/consent for the old bundled portrait,
possible explicit user-driven avatar removal after approval. No automatic
data deletion is authorized. Full UX overhaul follows planned design gate.
