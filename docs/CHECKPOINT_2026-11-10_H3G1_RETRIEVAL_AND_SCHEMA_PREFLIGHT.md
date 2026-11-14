# H3g.1 — Retrieval V2 and schema preflight (2026-11-10)

Branch: `feat/security-baseline-2026-11-03`, Draft PR #2. This is a development-only
change. No Railway, production, or paid AI calls.

## Local schema and migration safety

The repository's tracked `db/schema.rb` is from 2023. The owner's Linux Mint
file has an intentional local `M db/schema.rb` change. Its contents and the
running PostgreSQL schema have NOT been inspected here, so do not claim the
migration has run or that a local conflict is resolved.

The single H3g migration `20261110200000_create_ai_room_context_consents.rb`
adds an opt-in table, foreign keys and a unique room/member index. It does not
drop or rewrite other user/room/message tables.

### Owner-operated safe sequence

1. Inspect `git status -sb` and `git diff -- db/schema.rb`.
2. Create a private backup OUTSIDE the repository:
   `bash bin/backup_local.sh "$HOME/turbo_chat_private_backups"`.
   Verify its real output directory with:
   `bash bin/verify_local_backup.sh "/absolute/path/to/turbo-chat-TIMESTAMP"`.
   Do not upload the dump, storage tar or secrets to GitHub or chat.
3. Update without touching the local schema:
   `git fetch origin feat/security-baseline-2026-11-03` then
   `git merge --ff-only FETCH_HEAD`.
4. Run `bash bin/h3g_schema_preflight.sh --read-only`.
   This executes SELECT-only statements in the already-running local DB.
   If it reports a table/version conflict, STOP and investigate.
5. Review the output and prior schema diff before any deliberate migration.
   The Docker web entrypoint automatically invokes `db:prepare` when starting,
   so even `docker compose up -d --build` is a schema-change decision.

Never use reset, volume deletion, schema loading, or blind replacement of the
owner's schema. Read-only backup/checksum success is not a live restore
acceptance; an isolated restore drill exists separately.

## Retrieval V2 contract

- Latest 240 room-scoped nonempty text candidates, **current member authors
  only** and **only after every current member opts in**.
- Normalize and detect obvious secrets/PII on whole candidate messages before
  truncation/ranking. Filters are heuristic and can miss private information.
- Always retain the most recent usable incoming request and adjacent turns.
- Rank older excerpts using bounded Unicode keyword overlap from that request
  and a validated author hint. Keep at most three historical matches.
- Send **at most nine excerpts and 2400 chars** to the model, unchanged from v1.
  Up to 420 chars per excerpt. File bytes never enter the retrieval context.
- Return genuine message IDs, chronological order, retrieval version 2,
  and count of examined candidates. Not full-history memory or RAG.
- Query matching is deterministic and cheap, but may miss synonyms, implicit
  references, older-than-240 messages and unrelated task-specific evidence.

## Quality checks and acceptance

Tests cover facts older than 24 messages, language-aware terms, hints, DLP,
departed members, chronological source IDs, deterministic runs, bounded window,
and no message writes. Those are automated retrieval-contract checks, **not
measured model accuracy**.

A separately authorized synthetic evaluation dataset and optional real paid
provider call remain outstanding. Commercial readiness is not asserted.
