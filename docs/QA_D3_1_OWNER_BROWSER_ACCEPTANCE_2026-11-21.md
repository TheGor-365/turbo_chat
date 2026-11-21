# Turbo Chat V2 — D3.1 owner browser acceptance runbook (21 Nov 2026)

Status: **READY_FOR_MANUAL_QA / OWNER_QA_PENDING**, not ACCEPTED.
Source of truth: `docs/AI_MVP_IMPLEMENTATION_MASTER.md` §11 and `docs/AI_MVP_LIVE_STATUS.md` §S–T, draft PR #8. D3.1 is UX consolidation, **not** server-side completion of the shared Context Studio source adapter (D3.4) nor paid AI (T2/T3). This document is a human testing contract, not a record that the owner already tested anything.

## Preconditions and safety

- Use only **local development** (`http://127.0.0.1:3000`) and owner-controlled test rooms. `/rooms/3` is a known example, not a guaranteed room ID on every machine.
- Do not click Generate/paid requests, AI-filter if paid, final Send, Delete, or production deploy. In particular, do not modify existing valuable Project Circle instruction revisions solely to test naming; use a disposable private local QA room for persisted room-instruction cases.
- Preserve the original chat draft and attachments. No reset, checkout, restore, stash, or force pull of dirty local `db/schema.rb`; no migration, fixture reload, `db:reset`, or localStorage clearing.
- All app changes remain on `feat/ai-answer-readiness-master-2026-11-20`; PR #8 remains draft. Check the actual HEAD and its CI before counting acceptance. A green CI is not a green UX review.
- Browser: Chrome desktop at default zoom first; after safe first-round checks, light theme, narrow viewport 360px and optionally 200% zoom. Use screenshots (redact sensitive content), and record console exceptions if any.
- Source naming semantics: server `RoomAiInstructionRevision` holds instructions/revisions; the human-readable **name** and cross-room instruction template library are browser-local for now. No guarantee of cross-device sync. Default `Instruction #N` is a localized placeholder; editable value initially empty.

## T0 — Safe local sync (terminal; owner executes)

```bash
cd /path/to/turbo_chat
git status --short
git branch --show-current
git pull --ff-only origin feat/ai-answer-readiness-master-2026-11-20
git rev-parse --short HEAD
docker compose exec -T web yarn build &&
docker compose exec -T web yarn build:css &&
docker compose restart web
docker compose ps
```

Expected: correct feature branch; `git status --short` may still show ` M db/schema.rb` unchanged, pull is fast-forward, Yarn/Sass succeed, `web` running after restart. If pull/build errors, **stop and share exact terminal text**; do not modify/reset the schema. Chrome: Ctrl+Shift+R to clear cached assets.

## T1 — Four owner entrypoints and one modal at a time (read-only)

1. Open local private room. At composer see four visually uniform primary controls **Контекст AI / План AI / Сообщение / Комната**. Compare height, icon size, spacing, focus ring; ordinary Send remains separate. Screenshot A.
2. Type an unsent sentinel `QA_D3_1_UNSENT_<date>` in the regular composer; click **План AI**. It is an *informational/read-only* effective settings panel, not another source editor. Without applying or sending anything, click **Контекст AI** directly while Plan is visible. Expect Plan smoothly closes and Context Studio opens with no blank intermediate stuck state; no second Plan on top; sentinel still in composer on return. Screenshot B.
3. In Context Studio press **Escape**, then open **Сообщение**, close by Escape/outside click, then open **Комната** and close. Expect correct target modal/sheet, focus returns sensibly, no unintended Send, no changed chat draft. Screenshot C.

Pass: all four triggers navigate without duplicates; direct Plan→Context switch works; Escape/outside closes; no draft loss and no provider usage. Fail P1: wrong panel, overlapping sheets, stuck backdrop, unexpected Send; P0: data loss/paid call or consent bypass.

## T2 — Name editing and instruction revision (write only in isolated QA room)

1. Use a **new/disposable private test room** rather than altering Project Circle's current instruction. Open Комната → **Цель беседы и инструкции**. If no revision exists, the inline title has empty value and localized default placeholder, e.g. `Instruction #1` in English. Screenshot D.
2. Click name and type `Project scope rules`, then Tab. It must remain **exactly** `Project scope rules` (never `Instruction #1Project scope rules`). Clear and type again, use Enter and refocus to check; ensure no old prefix, even after the panel rerenders. Screenshot E. If testing text save: enter a distinct harmless QA instruction and explicitly Save version **once**; expect version increments once, no new message, normal composer sentinel unchanged.
3. If you saved a QA revision: open the browser-local template library in a second **QA room** under the same user/profile, verify named set exists, load into draft; confirm nothing is sent and the second room revision is **not** saved until you deliberately click Save version. Do not expect template name to sync to other devices/profiles.

Pass: exact name after blur and Enter, server revision append-only and independent of unsent chat; cross-room local template is inert until explicitly loaded/applied. P0: messages sent or valuable instruction overwritten without opt-in; P1: auto-prefix returned or duplicate save; P2: placeholder styling.

## T3 — Draft and preview/undo preservation (no paid generation)

1. In QA/private room put two paragraphs into regular unsent composer. Optionally attach a harmless local text file (without secrets) and check its preview. Note message count and screenshot.
2. Open **Сообщение**. Check one editable working copy, visible style presets and clear Preview/Apply/Undo (depending on enabled feature mode). Change a **local style** or manually edit the working copy; close with Escape and reopen. Check ordinary Send was not triggered, and existing draft/attachment survived.
3. If a deterministic local edit or preview is available without a model request, inspect preview and Apply, then Undo. Verify original content is restorable. **Do not click Grok Generate or grant one-time paid authorization**. If the current view lacks deterministic Apply/Undo, mark `NOT_AVAILABLE` rather than inventing an action; D3.2 exists to consolidate that UX.

Pass: unsent content/attachments retained, no automatic Send, no paid API; changes clearly attributed to current message. P0 data loss/automatic Send; P1 hidden duplicate context selection in normal editor; P2 excess controls/poor hierarchy.

## T4 — Context Studio clarity (read-only, no AI calls)

1. Open Context Studio; compare **Общий** vs **AI Answer** effective selection. Select all vs one incoming (if needed), but do not apply without intent. Distinguish `наследует` from `свой` and current effective count.
2. Inspect **Мои наборы**. Existing sets may be saved browser-locally; inspect a set but don't delete any. Verify the overview shows which function uses which set and that selection/search preview does not silently alter another function.
3. Check that `Все сообщения` means **available eligible history for selection**, not all text sent to model. Read the bounded Answer notice (currently up to 9 verified excerpts / 2400 characters and 240 eligible candidates). No paid AI filter or generation.

Pass: no ambiguous scope; clear effective and saved-vs-draft state; per-tool override does not silently rewrite general selection. P1 if dashboard claims applied but not; P2 if status is difficult to read. Actual server-backed set persistence is **D3.4**, not a D3.1 pass criterion.

## T5 — Visual accessibility and responsiveness

- Desktop dark/light: no clipped overlay, nested scrolling traps, inconsistent four-button height, or unreadable low contrast. Context Studio and Room/Message modal scroll independently of page; bottom actions remain reachable.
- Width 360px and 200% zoom: buttons wrap/use space logically, content fits horizontally, `Escape` and keyboard Tab function, overlays do not trap the close control below viewport.
- Reduced motion (optional): closing/opening must still finish; motion should respect OS preference. Annotate exact viewport/theme/zoom with screenshots.

## T6 — Existing H3 compatibility (no paid model)

- The advanced historical H3 source review and Client Brief tools are intentionally retained until D3.4 runtime adapter. Do **not** delete them merely because Context Studio now owns primary source selection.
- Open advanced section only to verify it is not broken/accidentally authorizing a request. Existing previous named templates and text must remain; make no paid request or Send. Note duplicate UX as **known debt** rather than accepting silent migration.

## Joint review / scorecard

For every scenario report: `PASS | FAIL | PARTIAL | NOT_TESTED`, screenshot number, theme and viewport, exact operation, expected vs actual, severity, and whether content was persisted server-side or merely browser-local.

Severity:
- **P0 blocker:** accidental Send, paid request without consent, data loss, unauthorized source reveal, owner instructions overwritten.
- **P1 functional/clarity:** wrong modal handoff, broken rename, duplicate/inconsistent effective setting, inaccessible buttons or broken workflow.
- **P2 polish:** spacing, labels, animations, visual density or contrast with no workflow break.

Evaluate six dimensions `0=unusable / 1=friction / 2=clear`:
1. Discoverability (four entrypoints);
2. Scope/authority (who and what each setting affects);
3. Edit–preview–undo correctness;
4. Save/restore and inheritance clarity;
5. Motion, focus, responsive layout;
6. Safety/no Send/no paid/no context leakage.

Acceptance rule: **no P0 or P1**, T1/T2/T3/T4 core checks pass, and each of six dimensions >=1 (prefer >=10/12). If any P0/P1, log it and fix within feature PR before marking D3.1 ACCEPTED. OWNER must explicitly confirm.

### First owner response requested

After T0+T1 submit **two screenshots**: A (composer with all four primary buttons and unsent sentinel), B (Context Studio opened from visible AI Plan), plus `git rev-parse --short HEAD` and any abnormal behavior. Do not perform T2 or T3 until the initial joint review; the assistant will interpret and record accurate QA results with date/source in `AI_MVP_LIVE_STATUS.md`.

No automated clicks, requests, migrations, deployment, paid AI or merge are authorized by this test plan alone.
