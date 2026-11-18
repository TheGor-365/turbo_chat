# L3.2a.3 — Stimulus message-search feedback

- Localize dynamic searching, rate-limit, unavailable, invalid response and network failure statuses via server-supplied data attributes.
- Keep DOM contract, debouncing, fetch credentials, room-scoped URL, Turbo Frame, AbortController and focus behavior unchanged.
- Rails locale catalogs remain the single source of strings; no parallel JS translation catalog or hardcoded language detection.
- Test all four locales and unchanged room/message counts.
- Requires `yarn build` in local dev in addition to web restart to update esbuild output.
- Separate subsequent phase handles realtime-health, peer-presence and typing JS statuses.
