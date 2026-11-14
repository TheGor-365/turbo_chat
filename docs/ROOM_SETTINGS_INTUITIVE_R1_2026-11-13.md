# R1 Room settings — intuitive categories and compact workspace

Updated 2026-11-13. Branch `feat/security-baseline-2026-11-03`, Draft PR #2.

## Owner feedback
The working Edit draft improvements and six visible AI preset cards were accepted.
Room settings remained too wide and busy: a fully expanded translation panel,
an unexplained Detailed writing tools switch, a long row of AI-style buttons,
and then Writing assistance below the fold. Users must read every line to
locate a relevant control.

## UI contract
- A centered content area capped at 870px; existing topbar and room/device
  identity retained.
- Primary task **Writing style** first. Six existing presets remain visible in
  an explicitly three-column desktop grid (two columns at small widths),
  each with icon, label and description. Preset IDs and Stimulus actions
  are untouched.
- **Writing assistance** stays fully visible, with the three original switches,
  disclosure controls, their permission diagnostics and logic unmodified.
  Only the existing heading icon gets stronger visual presentation.
- **Перевод входящих** and **Вид чата** become two clearly labeled,
  icon-led, click-open native disclosures. The state of translation's toggle
  remains visible on the collapsed translation tile; the translator continues
  processing messages even when the tile is closed.
- The controls remain in the DOM. No AI consent, status or existing
  preference is reset by disclosure toggling; all controls retain their
  existing Stimulus targets and user actions.
- Escape and the existing Close button dismiss the dialog as before. The
  original unsent draft remains on the composer.

## Testing
- Rails/Chrome verifies the desktop three-column and mobile two-column style
  grid, expanded preset choices, 870px maximum content width, accessible
  category icon controls, click disclosure, and unchanged three switches.
- Existing incoming-translation system tests now click the translation
  disclosure before changing source language or opt-in. Existing detailed
  tool tests intentionally open the display section first.
- No migrations, destructive commands, paid AI calls, Railway changes or
  main-branch merge. Local `db/schema.rb` must remain untouched.

## Remaining UX work
Manual owner acceptance at 320px and desktop; next product feature is
clearer AI Workspace Client Brief primary action and a separately reviewed
Share → Review → Approve/Reject lifecycle for room members.
