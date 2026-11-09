# frozen_string_literal: true

module AiWorkspace
  # H3a: an ephemeral, own-draft-only preflight. Deliberately does NOT imply
  # durable consent, financial approval, or authorization for an outbound API
  # call. The Gateway must remain closed until those server-side gates exist.
  class OwnDraftPreflight
    def initialize(pipeline: ContentPipeline.new)
      @pipeline = pipeline
    end

    def prepare(actor:, room:, draft_text:, preset_id:, approved_preview: false)
      raise Errors::ConsentRequired, "Manual approval required." unless approved_preview == true
      preset = PresetRegistry.bundled.fetch(preset_id)
      # H3 initial use case is polishing the author's own unsent text, never
      # selected chat history, attachment bytes or implicit member context.
      raise Errors::InvalidPreset, "Only draft polishing is available." unless preset.operation == "beautify"

      @pipeline.prepare(actor: actor, room: room,
        source: "own_draft", source_ids: [], operation: "beautify",
        preset: preset, draft_text: draft_text)
    end
  end
end
