# G1/B17 — Unified Task Sheets: CI-green code and owner visual gate

**Checkpoint date:** 2026-11-23 (Asia/Yerevan)  
**Repository:** `TheGor-365/turbo_chat`  
**Base:** `feat/ai-answer-readiness-master-2026-11-20` @ `a84728c278c1ec059d3eae3bc73d0925d48c8fa3`  
**Implementation:** [Draft PR #10](https://github.com/TheGor-365/turbo_chat/pull/10), feature-on-feature, **NOT main**.  
**Verified initial B17 code SHA:** `39c68e215605eeb62cd1b759e0ed55434bff14f7` (full run evidence below).  
**Source of owner request:** actual local `/rooms/3` desktop and Chrome 400×793 screenshots, with 6 tab states and unsent `QA B16 — НЕ ОТПРАВЛЯТЬ` draft.

## In scope / code implemented

- Plan-shaped bottom-aligned task surfaces: Plan / Context / Instructions / Message / Room, with a compact Status surface.
- Shared responsive height and bottom docking **measured above the real composer**; protect ordinary Send and input from cover/displacement.
- Pointer/keyboard grip on four canonical dialogs; Plan retains its own established resize owner. Instructions and Room remain one original dialog with two views.
- Uniform navigation tab visual language; active mobile Status differentiated; leaner Plan-like card styling for Message/Room/Instructions.
- Subtle canvas gradient and counter-direction message bubble gradient using dark/light theme tokens.
- Existing room preferences, instruction append-only revisions, consent/ACL, bounded Context Studio, human draft and Send behavior remain the authoritative implementation; no new paid API, auto-send, database migration or duplicated preference owner.

## Exact-code-sha GitHub Actions evidence (CI green, owner QA NOT accepted)

| Workflow | Run | Result |
|---|---|---|
| [Focused Chrome](https://github.com/TheGor-365/turbo_chat/actions/runs/45069939045) | 45069939045 | SUCCESS |
| [Baseline Rails CI](https://github.com/TheGor-365/turbo_chat/actions/runs/45069939081) | 45069939081 | SUCCESS |
| [Security audit](https://github.com/TheGor-365/turbo_chat/actions/runs/45069939115) | 45069939115 | SUCCESS |
| [Production image build, no deploy](https://github.com/TheGor-365/turbo_chat/actions/runs/45069939044) | 45069939044 | SUCCESS |

`locale-integrity.yml` does **not trigger** on a UI-only PR because it has narrow `paths:` filters, but `ruby script/check_locale_syntax.rb` passed as part of both green Baseline and Focused Chrome. `docker-dev-smoke.yml` is also **not triggered** (no Compose/Dockerfile.dev changes); do **not** claim its exact-SHA run passed. Production image smoke is not a substitute for the owner local Compose acceptance.

**Historical failed intermediate commits remain in PR #10 comments and have not been concealed.** These exposed: inline Plan pushing composer offscreen, fixed Plan covering composer controls, sticky tabs intercepting style picker, and a previously invalid outside-click target. The green SHA above includes corrections without weakening consent, spending, source or Send checks.

## Release gates / remaining work

1. **Owner local update ONLY with guardrails**. The last owner state is on the PR #8 B16 branch; `db/schema.rb` locally modified and its cause not established. Back up this file outside the repo with owner-set 0700 permissions. Confirm the expected B16 HEAD and working tree, `git fetch` the B17 review branch without resetting any local file. Checkout/merge only after safety checks, then rebuild JS/CSS and restart web without DB migration/volume resets. No push, merge, main, production or paid model call.
2. **Owner visual acceptance (dark/light)**: desktop 1440px plus mobile 400×793 / 390×844. Open Status → Plan → Context → Instructions → Message → Room; compare height/bottom docking, tap targets, drag grips, scroll, controls under sticky nav, close/toggle/Escape/outside click and editor text preservation. Check both incoming/outgoing gradient contrast, theme persistence and layout at device width. Test draft is NOT to be sent.
3. **Then D3.2 + D3.3**, after screenshots and any fixes: slim Message/Beautify and Room/Instructions internals to one editor/preview/apply/undo and one inherited room preference owner. Gradual move of old H3 actions to canonical services only with equivalent source/consent/cost/Undo regression checks. Do not delete legacy H3 reviewer just to declutter before D3.4 server adapter.

## Operational ledger

| Property | Status |
|---|---|
| Source code + Draft PR | `CODE_COMMITTED` |
| Four eligible CI checks @ code SHA above | `CI_GREEN` |
| Locale/Docker standalone workflows | `NOT_TRIGGERED_BY_PATH_FILTER` |
| Owner local branch update | `AWAITING_OWNER_ACTION` |
| Light/dark, desktop/400/390 screenshots | `OWNER_QA_PENDING` |
| PR merge / production release | `BLOCKED` |
| Local dirty `db/schema.rb` | `PRESERVE / NO_RESET / NO_MIGRATE` |

Any later B17 code or tests commit supersedes this exact SHA for release decisions. Always read PR #10 current head and Actions before calling current HEAD CI-green.
