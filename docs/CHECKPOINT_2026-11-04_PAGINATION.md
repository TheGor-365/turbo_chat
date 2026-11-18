# P1 checkpoint — historical message pagination

Date: 2026-11-04.

An existing mismatch between `@pager` and the controller's actual `@pagy`
made page 2 of room history unreliable. Both Turbo Frame page template and
the pager partial now consistently use their Pagy instance/local.

Added HTTP integration acceptance with >25 messages to assert frame
pagination actions and a follow-on Load More link, plus negative coverage
for a nonmember using a direct page parameter.

This is a bugfix; visual scroll behavior and mobile UX remain to be
verified on the user's local browser.
