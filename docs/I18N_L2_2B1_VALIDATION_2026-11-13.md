# Turbo Chat — L2.2b.1 Account validation localization

- ActiveRecord User form field labels and validation failures moved into
  `config/locales/account_validation.<locale>.yml` for EN/RU/HY/ES.
- Custom display-name format uses a **symbolic message key** (Rails keeps
  the internal error code :invalid); avatar type/size use typed error codes.
  No English strings remain in these model validations. Allowed characters,
  MIME types, size limits, and validations remain exactly the same.
- Generic account error strings cover blank, invalid, taken, confirmation,
  too_short and too_long. Devise status/flash locales are separate (L2.2a).
- Tests assert catalog parity, variable parity, actual model validation
  errors in four locales, and unchanged typed errors for avatar files.
- No database migration, access policy change, account mutation, AI request,
  registration enablement, SMTP/production config or Docker volume change.

Deferred to L2.2b.2: attachment *preflight* guard error messages,
localized email body templates, controllers' other notices and strict audit.
Do not perform real password changes or submit uploads from personal accounts
for language-only verification.
