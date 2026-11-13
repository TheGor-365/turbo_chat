# L3.1b.3 — Localized inbox preview dates

- Last-message preview remains author-only, with no body leak or extra queries.
- Text and relative timestamp now use ui.room_list and Rails
  datetime.distance_in_words on all four locales (EN/RU/HY/ES).
- English remains identical to prior strings including "ago".
- Native Rails helper thresholds retained; locale-specific duration strings
  use abbreviations where inflection/plural rules would otherwise need
  a more extensive CLDR implementation (notably Russian).
- Existing datetime ISO8601 attributes and unread logic unchanged.
- Tests assert room name/author, locale-aware 3-day timestamp, no private
  message body exposure and stable Message.count.
- No JS/CSS, migration, message editing or delivery behavior changed.
