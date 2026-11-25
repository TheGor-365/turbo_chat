# frozen_string_literal: true

module AiWorkspace
  # Classification of an explicit Send workflow, not authorship detection.
  # No provider call, database write, browser-supplied origin or implicit Send.
  class MessageOrigin
    VERIFIED_WORKFLOWS = {
      "own_draft_edit" => "ai_edited",
      "model_answer" => "ai_generated",
      "synthetic_answer" => "synthetic",
      "answer_unclassified" => "ai_assisted_legacy"
    }.freeze

    # Call only for the explicit AI Send path. A missing/invalid proof is
    # rejection (nil), never a fallback to manual or legacy classification.
    def self.verified_ai(token:, actor:, room:, source_text:)
      workflow = DraftProvenance.verified_workflow(
        token: token, actor: actor, room: room, source_text: source_text
      )
      VERIFIED_WORKFLOWS[workflow]
    end

    # Read-side compatibility for old records and old application writers.
    # A legacy false flag is not evidence of human-only authorship.
    def self.display_kind(origin:, ai_assisted:)
      return "unknown" unless ai_assisted == true || ai_assisted == false
      if origin.nil?
        return ai_assisted ? "ai_assisted_legacy" : "unknown"
      end
      return "manual" if origin == "manual" && ai_assisted == false
      return origin if ai_assisted == true && VERIFIED_WORKFLOWS.value?(origin)

      "unknown"
    end
  end
end
