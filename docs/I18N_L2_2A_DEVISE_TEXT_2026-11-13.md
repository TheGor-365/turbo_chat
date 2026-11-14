# L2.2a — Devise text and password reset UI
Date: 2026-11-13. Source: existing Devise 5 locale keys, user-confirmed L2.1.

- Added full Devise message catalogs in ru, hy, es from the existing en reference:
  authentication failures, session notices, registrations, recoverable,
  confirmable, lockable, OmniAuth, mail subjects and Devise error summaries.
- Translated the reset-password form and optional Devise footer links to
  four languages. English UI strings remain identical to the previous UI.
- No changes to authentication middleware, session handling, password
  security, tokens, signup policies or SMTP. A localized subject does not
  imply email sending works or localized email bodies (deferred).
- Checks: catalog key and %{placeholder} parity, four reset page renders,
  invalid-login notice in each browser locale. The latter will catch if
  Warden loses request locale outside controller context.

Next separate L2.2b: ActiveModel/Devise validation message translations,
model-specific field labels, upload errors and localized email bodies.
