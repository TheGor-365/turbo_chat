# Signal Deck 2 — D1 visual acceptance (pending)

Source standard: owner-supplied `TURBO_CHAT_SIGNAL_DECK_DESIGN_SYSTEM_V2_2026-11-17.md` (17 November 2026).
Baseline: `f4ae7bcb48718423473c11690f2f315081e88199`, existing Draft PR #2. This branch deliberately targets the feature branch, **not** main.

## Changed
- Canonical dark/light/system semantic tokens in `signal_deck_tokens_v2.scss`; legacy aliases preserved.
- Remove duplicate root theme declarations from V1 and refinement; preserve other existing component CSS.
- Remove unscoped legacy 10px white scrollbar; use native application-scoped 6px/ thin scrollbar.
- Standard fields: quiet border with retained keyboard focus-visible outline.
- Room-first screen: shell/canvas tonal separation, readable messages, softly elevated bubbles, consistent avatar geometry.

## Not changed
- No ERB markup, translations, Stimulus controllers, model, route, ACL, consent, AI billing,
  provenance, database migration, server-side send, media or draft behavior.
- No changes to deployment, `main`, Railway or owner-local `db/schema.rb`.

## Human acceptance (NOT verified yet)
1. Compare `/rooms/3?ui_locale=ru` before/after at 1440+ and 390/320 CSS px, dark and light.
2. Verify theme cycle dark -> light -> system without reload and system color scheme transition.
3. Focus standard input by keyboard and mouse; focus visible via keyboard but no persistent neon glow.
4. Send manual message and check both sides, long text, media, reaction, original/translation and scroll position.
5. Open room settings and message settings; ensure no horizontal overflow or broken scrollbars.
6. Verify toolbar, camera/attach, both manual/AI editors and their independent Send arrows unchanged.
7. Check Chrome and Firefox, zoom 200%, reduced motion.
8. Require exact-SHA Rails/Chrome, security, Docker Compose, production-image workflow results and owner screenshots before merge.

Status: implementation proposal for visual review; **NOT production accepted**.
Do not merge or deploy until owner approves the visible room first. Continue with one screen per acceptance.
