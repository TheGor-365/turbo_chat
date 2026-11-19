# ADR — Business presets + Content Transformation V1.0 (2026-11-14)

## Scope and product purpose

This slice makes the commercial **Conversation → Deliverable** journey inspectable
without adding another paid AI step or a separate bot interface. It builds on
SmartWorkflowV1 and the owner's accepted inline source review. It is NOT a new
provider workflow, an autonomous agent or an approved export action.

Code-owned, versioned preset metadata:
- `agency/client_brief@1` → client brief
- `agency/client_proposal@1` → client proposal
- `agency/client_summary@1` → conversation summary

Each has a fixed task, audience, tone, existing H4-required sections, capped
source count, output budget from `ConversationTaskV1`, and human review topics.
The separate six `PresetRegistry` entries remain **writing styles**; they are
not replaced or silently used as business authorization. Every preset uses
`explicit_save`; reviewed is not approved.

## Operation boundary

`ContentTransformationV1#plan!` accepts a server-created bounded
`ReplyContextBuilder::Bundle`, live authenticated actor and room, selected
source IDs, matching task kind and exact code-owned preset version.
It rechecks current unanimous private-room consent, membership, same-room
current authors and the selected subset. It produces **only inert metadata**:
preset key/version, document format, section names, review topics and source
count. It never emits excerpts, sends model prompts, reserves a budget,
persists a document, confirms a claim or sends a chat message.

The preview endpoint still issues the existing 10-minute signed source receipt.
The plan is advisory, based on the initially checked sources; changing the
task invalidates the visible suggestion. At paid click, existing
`SourceSelection.apply!` and provider-side authorization independently rebuild
the actual sources. A plan is never permission to execute. Only the user's
subsequent explicit Generate and Save actions cross those separate gates.

## Next gate

Add a complete, human-controlled business-preparation flow which can adjust
audience, format and brand rules as bounded **data**, rather than arbitrary
trusted system instructions. Connect a *versioned business preset reference*
to the existing context task execution only after verifying all source,
budget, and review gates. Avoid duplicating H5 Save v1/v2 logic; keep
approval and export separate from Save, and normal chat independent.
