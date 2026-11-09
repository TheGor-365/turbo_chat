# Turbo Chat — unified UI/UX redesign brief (captured 2026-11-04)

## Explicit user requirements
- Replace the entire current generic/educational visual language with an original,
  premium, consistent product concept, never a reskinned Bootstrap template.
- Scope: landing page, sign up/in/recovery, conversation list, public room
  discovery, direct messages, composer, attachments, message actions, account,
  empty/loading/error states, toast, drawer, popover, **every modal**.
- A coherent visual system across every viewport and state: semantic tokens,
  typography, spacing, elevation, transitions, iconography, component behavior.
- Use abundant **high-quality, expressive but legible icons** instead of
  excessive text, without sacrificing keyboard navigation, accessible names,
  tooltips or clarity. Avoid a jumble of mismatched icon families.
- Responsive mobile-first, 320/390/768/1024/1440 widths; support touch,
  focus states, contrast, screen readers, reduced-motion; performance budget
  and safe motion durations.
- Realtime interactions should feel immediate: progress, sending/sent/error,
  upload preview/progress, hover/focus, inline edit, confirmations, notices,
  scroll/reconnect, optimistic UI only when backed by reliable state.

## Agreed sequencing (DO NOT start full redesign yet)
1. Close P0 server authorization, data protection and release reliability.
2. Complete and verify real product flows in two browsers, upload/download,
   reconnect, account recovery and navigation.
3. Perform professional UX research on relevant messengers (patterns,
   usability, not cloning), then **three distinct visual concepts**.
4. Choose a concept with owner approval and turn it into implementation
   tokens/component inventory/accessibility specification.
5. Implement in Rails 8 + Hotwire + Stimulus, existing build pipeline and
   responsive CSS; avoid new JS framework without demonstrated need.
6. Test the entire screen/modal/state inventory in actual browser viewports.
7. Capture *real* UI screenshots/video and evidence manifest for portfolio.

## Available design tools to evaluate on that phase
- Product Design: research/audit/ideation/prototype/visual QA. This skill
  explicitly requires ChatGPT Work for its complete workflow.
- MagicPath: editable interactive UI components and design systems,
  including component install-plan export; inspect API quotas first.
- Canva: branded assets, banners, covers, presentations, social export;
  do not mistake editable illustrations for product code.
- tldraw: information architecture, flows, component maps and wireframes.
- Design approval is a separate gate; tool availability does not mean a
  final design is generated, accepted, licensed or integrated today.

## UX quality gate
No screen omitted; desktop/mobile screenshot acceptance; original brand;
one icon family (licensed), consistent motion; focus/keyboard/ARIA, no
icon-only controls without accessible names and discoverability; clear
loading/empty/error feedback and working actions. Do not claim completion
without owner visual acceptance and functional tests.


## Owner UI backlog update — 2026-11-09

Owner screenshots confirmed Gate 2B.1 offline preview locally but rejected remaining generic Bootstrap hero/buttons, Account fields/cards, browser-native Activity/AI dropdowns, placeholder favicon and default Rails static error pages. Full factual observations and implementation gates: [UI_UX_BACKLOG_2026-11-09_OWNER_REVIEW.md](UI_UX_BACKLOG_2026-11-09_OWNER_REVIEW.md). **No sweeping redesign now.** Prioritize non-mutating Home GET correction, keep implementing AI Gate 2B.2, then D3.2 accessible filters, D5.1 settings, D4.5 Home, D0.2 brand/error, D6 all-viewport QA. Existing focus outlines and real Devise/ACL behavior are not optional. Status: queued, NOT built.
