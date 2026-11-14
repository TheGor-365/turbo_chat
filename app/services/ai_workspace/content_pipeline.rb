# frozen_string_literal: true

module AiWorkspace
  # Offline preparation only. No gateway invocation, provider call, storage,
  # broadcast, persistent request or implicit room history retrieval.
  class ContentPipeline
    SOURCES = %w[own_draft selected_messages approved_context].freeze
    Row = Struct.new(:source_id, :text, :warnings, keyword_init: true)
    Prepared = Struct.new(:source, :operation, :preset_snapshot, :rows, :characters, :target_locale, keyword_init: true)

    def initialize(context_policy: ContextPolicy.new)
      @context_policy = context_policy
    end

    def prepare(actor:, room:, source:, source_ids:, operation:, preset:, draft_text: nil, target_locale: nil)
      raise Errors::InvalidPreset, "Invalid preset." unless preset.is_a?(PresetDefinition)
      raise Errors::InvalidSelection, "Invalid operation." unless operation == preset.operation
      raise Errors::InvalidSelection, "Invalid locale." unless target_locale.nil? || PresetDefinition::LOCALES.include?(target_locale)
      raise Errors::InvalidSelection, "Invalid source." unless SOURCES.include?(source)
      # No durable consent model yet; future approved context is not a loophole.
      raise Errors::ConsentRequired, "Context consent is unavailable." if source == "approved_context"

      @context_policy.authorize_actor!(room: room, actor: actor)
      rows = case source
      when "own_draft"
        raise Errors::InvalidSelection, "Invalid selection." unless source_ids == []
        normalized = Preprocessors::Text.call(draft_text)
        [Row.new(source_id: nil, text: normalized.text, warnings: normalized.warnings).freeze]
      when "selected_messages"
        raise Errors::InvalidSelection, "Invalid selection." unless draft_text.nil?
        # A preset may narrow the global 8-message manual gate, never expand it.
        maximum = preset.snapshot.fetch("context").fetch("max_messages")
        unless source_ids.is_a?(Array) && source_ids.size.between?(1, maximum)
          raise Errors::InvalidSelection, "Invalid selection."
        end
        review = @context_policy.review(room: room, actor: actor,
          operation: operation, source_ids: source_ids)
        review.rows.map do |item|
          normalized = Preprocessors::Text.call(item.text)
          warnings = item.truncated ? (normalized.warnings + [:source_truncated]).freeze : normalized.warnings
          Row.new(source_id: item.message_id, text: normalized.text,
            warnings: warnings).freeze
        end
      end

      # Preset is a frozen value snapshot; none of this data is persisted.
      Prepared.new(source: source, operation: operation, preset_snapshot: preset.snapshot,
        rows: rows.freeze, characters: rows.sum { |row| row.text.length }, target_locale: target_locale).freeze
    end
  end
end
