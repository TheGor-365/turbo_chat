# R1 UX editor clarity — Edit draft / Room settings

Date: 2026-11-13. Draft PR #2 `feat/security-baseline-2026-11-03`.

## User evidence and scope

Owner accepted the simplified chat and incoming EN→RU translation using two real
Chrome sessions. Follow-up screenshot showed Edit draft as a long vertical
sequence of similarly weighted text actions and the six built-in AI presets
collapsed in both Edit draft and Room settings. Request: preserve the top
navigation/context, keep existing colors, leave the Writing assistance
switches as-is, use icons and visual spacing, and show style tiles by default.

## Implementation

- Both existing native style disclosures start **open**. Six icon cards are
  visible with short explanations and the active style. They remain
  manually collapsible and retain `aria-pressed`, exact preset IDs and the
  existing `choosePreset` Stimulus action.
- Edit draft shows clear icon-led sections: writing style, working copy
  (only once present), AI actions, privacy/pricing details, and finish editing.
- The conversational tools (local templates, source inspection, reply,
  task picker, manual review) form a responsive icon-card grid. Existing
  API calls, client-side state targets and paid-action gating are unchanged.
- **Writing assistance** switches, their own details/permissions and controls
  are intentionally untouched. Room settings gains only a clearer visible
  writing-style card group.
- Short preset captions are *presentation only*. Selected style labels sent to
  the UI are read from `.sd-ai-preset-name`, not the entire button text,
  keeping existing app state and persisted preset values unchanged.
- No new permissions, paid API calls, migrations, attachment changes,
  message changes, deployment, or production data are part of this commit.

## Acceptance

- Rails/Chrome: six icon cards visible without click; selected style updates
  both views; captions never pollute stored style labels.
- All three Writing assistance switches and explanatory disclosures still
  exist in the same structure.
- At 320px cards stay within the modal, keyboard dismissal preserves the
  unsent message, no automatic Send.
- Existing manual Grok suggestion, contextual task, H4 review, focus, mobile,
  consent and recovery tests must remain green.
