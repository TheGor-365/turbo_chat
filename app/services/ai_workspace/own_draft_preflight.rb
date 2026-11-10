# frozen_string_literal: true

module AiWorkspace
  # H3a: an ephemeral, own-draft-only preflight. Deliberately does NOT imply
  # durable consent, financial approval, or authorization for an outbound API
  # call. The Gateway must remain closed until those server-side gates exist.
  class OwnDraftPreflight
    def initialize(pipeline: ContentPipeline.new)
      @pipeline = pipeline
    end

    def prepare(actor:, room:, draft_text:, preset_id:, target_locale: nil, approved_preview: false)
      raise Errors::ConsentRequired, "Manual approval required." unless approved_preview == true
      preset = PresetRegistry.bundled.fetch(preset_id)
      # H3f.3: all six reviewed modes are own-unsent-draft only.
      # Translation always requires an explicit target language selection.
      if preset.operation == "translate"
        unless PresetDefinition::LOCALES.include?(target_locale)
          raise Errors::InvalidSelection, "Choose a supported translation language."
        end
      elsif !target_locale.nil?
        raise Errors::InvalidSelection, "Unexpected translation language."
      end
      @pipeline.prepare(actor: actor, room: room,
        source: "own_draft", source_ids: [], operation: preset.operation,
        preset: preset, draft_text: draft_text, target_locale: target_locale)
    end
  end
end
