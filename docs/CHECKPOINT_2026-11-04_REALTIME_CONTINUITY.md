# Realtime continuity gate / 2026-11-04

Owner screenshots: recipient only saw the new photo after F5,
despite two users being in the same room. This is a release-blocking
failure of realtime acceptance, regardless of Rails CI passing.

Observed differences:
- Earlier browser system tests used ActionCable `async`; Redis-based
  browser tests were introduced on the previous commit and passed.
- The owner may have had a stale websocket after a Docker container
  recreation. This is **plausible, not yet proven**. The new status
  indicator must reveal whether the second tab has confirmed its stream.

Implementation:
- Show connection state by observing `turbo-cable-stream-source[connected]`.
- Primary transport remains authenticated Redis-backed ActionCable.
- Fallback endpoint `GET /rooms/:room_id/messages/sync?after_id=N`
  validates login and current membership, is throttled and returns
  a bounded Turbo Stream of at most 50 messages per request.
- On connection/reconnection/visibility change, sync missing messages.
  While disconnected, try HTTP catch-up every 12 seconds.
- GET is read-only; never touches or resets the message composer.
- Button "Sync messages" is an explicit rescue without full F5.
- Duplicate messages should be deduplicated by Turbo append's existing
  id-handling. Paginated older history is not replaced.
- Tests cover allowed/denied sync, invalid cursor and disconnected browser
  catch-up; continue to validate genuine Redis Chrome acceptance.

This is resilience, NOT proof that stale WebSocket connectivity has
been fixed on the user's Linux machine. Next user acceptance must
show "Live · WebSocket connected" on BOTH tabs and delivery without
refresh in BOTH directions. If not, inspect Chrome WebSocket frame/log
and container logs before changing the transport.
