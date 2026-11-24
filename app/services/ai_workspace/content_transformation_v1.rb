# frozen_string_literal: true

module AiWorkspace
  # A reviewable, NO-SPEND plan for an already authorized context preview.
  # It has no provider, storage, queue, approval, export or Send capability.
  # It is never an authorization token for a later paid request.
  class ContentTransformationV1
    VERSION = 1
    Result = Struct.new(:version, :preset_key, :preset_version, :kind,
      :output_format, :required_sections, :review_checks, :source_count,
      :requires_human_review, :execution_state, keyword_init: true)

    def initialize(access: RoomContextAccess.new)
      @access = access
    end

    def plan!(room:, actor:, bundle:, task_kind:, preset_key:,
      preset_version: BusinessPresetRegistryV1::VERSION, selected_source_ids:)
      preset = BusinessPresetRegistryV1.fetch!(key: preset_key, version: preset_version)
      unless task_kind.instance_of?(String) && preset.task_kind == task_kind
        raise Errors::InvalidPreset, "Business task does not match preset."
      end

      # Recheck live membership and unanimous consent. Caller must independently
      # rebuild sources and verify the signed receipt before ANY paid execution.
      @access.authorize!(room: room.reload, actor: actor)
      validate_bundle!(bundle: bundle, room: room, actor: actor)
      ids = validate_selection!(bundle: bundle, selected_source_ids: selected_source_ids,
        max_sources: preset.max_sources)

      # Verify that all selected references still belong to current participants
      # in this exact room. No other message bodies are fetched or returned.
      allowed_ids = ContextAuthorPolicy.new.resolve(room: room, actor: actor).allowed_author_ids
      current = room.messages.where(id: ids, user_id: allowed_ids).pluck(:id, :user_id).to_h
      raise Errors::InvalidSelection, "Source review changed." unless current.size == ids.size
      incoming = bundle.rows.any? do |row|
        ids.include?(row.message_id) && current.fetch(row.message_id) != actor.id &&
          row.speaker != "you"
      end
      raise Errors::InvalidSelection, "Include an incoming message." unless incoming

      Result.new(version: VERSION, preset_key: preset.key,
        preset_version: preset.version, kind: preset.task_kind,
        output_format: preset.output_format,
        required_sections: preset.required_sections, review_checks: preset.review_checks,
        source_count: ids.size, requires_human_review: true,
        execution_state: "suggestion_only").freeze
    end

    private

    def validate_bundle!(bundle:, room:, actor:)
      max = ReplyContextBuilder
      unless bundle.is_a?(max::Bundle) &&
          bundle.version == max::VERSION && bundle.room_id == room.id &&
          bundle.actor_id == actor.id && bundle.rows.is_a?(Array) &&
          bundle.rows.size.between?(1, max::MAX_MESSAGES) &&
          bundle.source_ids.is_a?(Array) &&
          bundle.source_ids == bundle.rows.map(&:message_id) &&
          bundle.source_ids.uniq.size == bundle.source_ids.size &&
          bundle.characters.is_a?(Integer) &&
          bundle.characters.between?(1, max::MAX_CONTEXT_CHARS)
        raise Errors::InvalidSelection, "Invalid approved context."
      end
      bundle.rows.each do |row|
        unless row.is_a?(max::Row) && row.message_id.instance_of?(Integer) &&
            row.message_id.positive? && row.text.instance_of?(String) &&
            row.text.valid_encoding? && row.text.length.between?(1, max::MAX_MESSAGE_CHARS) &&
            (row.speaker == "you" ||
              (row.speaker.instance_of?(String) && row.speaker.match?(/\Aparticipant_[1-9]\d*\z/)))
          raise Errors::InvalidSelection, "Invalid approved context."
        end
      end
    end

    def validate_selection!(bundle:, selected_source_ids:, max_sources:)
      ids = selected_source_ids
      unless ids.is_a?(Array) && ids.size.between?(1, max_sources) &&
          ids.all? { |id| id.instance_of?(Integer) && id.positive? } &&
          ids.uniq.size == ids.size && (ids - bundle.source_ids).empty?
        raise Errors::InvalidSelection, "Invalid source selection."
      end
      ids
    end
  end
end
