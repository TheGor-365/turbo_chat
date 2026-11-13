# Turbo Chat L1.0 — i18n foundation

Four UI locales: EN (default), RU, HY, ES. Cookie-backed selection already existed.

- `ui.<feature>.<key>` catalogs checked for **exact key parity**, nonempty strings
  and interpolation parity on every locale. Runtime English fallback is not a
  substitute for completed translation.
- Localized main navigation aria-label and all three theme-toggle states.
- `html.lang` is synchronized from server-rendered body metadata after Turbo
  visits (Turbo preserves the original html root).
- No change to chat bodies, permissions, consent, Grok, realtime or database.
- UI copy elsewhere intentionally remains untouched for staged translation.

Next: L1.1 guest/authenticated Home; L2 auth + Devise errors; L3 inbox and
room controls plus no-draft-loss locale-change tests; L4 AI tools; L5 deliverables
and JavaScript error states; L6 full hardcode inventory and 4-locale regression.

Tests:
`bin/rails test test/integration/ui_catalog_contract_test.rb test/integration/ui_locale_shell_test.rb`
