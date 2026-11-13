# L3.2a.2 — In-conversation search and history pager

Localized room-scoped search controls, feedback from server search results, result count, matching message aria, pagination and older-message loader. Search criteria, room-scoped ACL, Turbo frame IDs, 100-character guard and routes stay unchanged. Result timestamp now numeric UTC (`YYYY-MM-DD · HH:mm UTC`) to avoid English month names.

The Stimulus controller's dynamic feedback strings (Searching…, network errors, rate-limit) are deliberately deferred for a JS/catalog pass. No message writes, migrations or CSS changes. Integration coverage checks EN/RU/HY/ES and original message links.
