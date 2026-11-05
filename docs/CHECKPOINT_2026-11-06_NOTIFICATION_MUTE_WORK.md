# Gate 1 — Per-conversation notification mute

Scope: persist user-and-room mute preferences without touching existing conversation unread cursors or message delivery. New events are suppressed while mute is on; previous notification history remains unchanged. Require current room membership for updates; leave main and Railway unchanged. User-local database and schema.rb remain untouched until reviewed migration and green CI.
