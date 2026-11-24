# frozen_string_literal: true

require "digest"
require "json"

module AiWorkspace
  # S3, stage one: an immutable, provider-free generation preflight.
  # This is NOT a spend permit. The eventual dispatch must repeat ACL,
  # consent, goal/source version and budget checks immediately before use.
  class GenerationOrchestrator
    MODES = %w[beautify answer auto_reply].freeze

    Request = Struct.new(:mode, :actor, :room, :draft_text, :request_id,
      :confirmed, :preset_id, :target_locale, :writing_language, :writing_tone,
      :hint, :expected_goal_revision, :goal_source, :source_token, :selected_ids,
      :reply_target_id,
      keyword_init: true)

    Plan = Struct.new(:mode, :request_id, :room_id, :actor_id, :source,
      :source_ids, :prepared, :goal_snapshot, :preferences,
      :participant_ids, :consent_fingerprint,
      :provider_called, :budget_reserved, :message_sent,
      keyword_init: true)

    def initialize(own_draft: OwnDraftPreflight.new,
      context_builder: ReplyContextBuilder.new, access: RoomContextAccess.new)
      @own_draft = own_draft
      @context_builder = context_builder
      @access = access
    end

    def prepare(request:)
      unless request.is_a?(Request) && MODES.include?(request.mode) &&
          request.request_id.is_a?(String) &&
          request.request_id.match?(LocalBudgetLedger::REQUEST_ID) &&
          request.draft_text.instance_of?(String)
        raise Errors::InvalidSelection, "Invalid generation request."
      end

      # A policy or a selected mode cannot activate unattended processing.
      raise Errors::ProviderUnavailable, "Automatic replies are disabled." if request.mode == "auto_reply"
      raise Errors::ConsentRequired, "Confirm this request." unless request.confirmed == "1"
      actor, room = request.actor, request.room
      unless actor&.persisted? && room&.persisted? && room.reload.accessible_to?(actor)
        raise Errors::Unauthorized, "Conversation unavailable."
      end

      if request.mode == "beautify"
        prepare_beautify(request, actor, room)
      else
        prepare_answer(request, actor, room)
      end
    end

    private

    def plan(request, actor, room, source:, source_ids:, prepared:, goal: nil)
      Plan.new(mode: request.mode, request_id: request.request_id,
        room_id: room.id, actor_id: actor.id, source: source,
        source_ids: source_ids.freeze, prepared: prepared,
        goal_snapshot: goal&.public_snapshot&.freeze,
        preferences: WritingPreferenceResolver.for(user: actor, room: room).effective,
        participant_ids: (request.mode == "answer" ? room.participants.distinct.pluck(:user_id).sort.freeze : [].freeze),
        consent_fingerprint: (request.mode == "answer" ? consent_fingerprint(room) : nil),
        provider_called: false, budget_reserved: false, message_sent: false).freeze
    end

    def prepare_beautify(request, actor, room)
      unless request.draft_text.strip.present? && request.hint.nil? &&
          request.expected_goal_revision.nil? && request.source_token.nil? &&
          request.selected_ids.nil?
        raise Errors::InvalidSelection, "Beautify requires one human draft."
      end
      prepared = @own_draft.prepare(actor: actor, room: room,
        draft_text: request.draft_text, preset_id: request.preset_id,
        target_locale: request.target_locale, approved_preview: true,
        writing_language: request.writing_language, writing_tone: request.writing_tone)
      raise Errors::InvalidSelection, "Sensitive draft data." unless prepared.rows.first.warnings.empty?
      plan(request, actor, room, source: "own_draft", source_ids: [], prepared: prepared)
    end

    def prepare_answer(request, actor, room)
      unless request.draft_text.strip.empty? && room.is_private? &&
          request.preset_id.nil? && request.target_locale.nil? &&
          request.writing_language.nil? && request.writing_tone.nil? &&
          request.expected_goal_revision.is_a?(Integer) && request.expected_goal_revision.positive?
        raise Errors::InvalidSelection, "Answer requires an empty editor and current goal."
      end
      goal = current_goal!(request, actor, room)
      note = ContextReplyPromptV1.validate_hint!(request.hint)
      @access.authorize!(room: room, actor: actor)
      bounded = @context_builder.build(room: room, actor: actor, hint: note)
      selected = SourceSelection.apply!(room: room, actor: actor, bundle: bounded,
        hint: note, source_token: request.source_token, selected_ids: request.selected_ids)
      if request.reply_target_id
        unless request.reply_target_id.instance_of?(Integer) &&
            selected.rows.any? { |row|
              row.message_id == request.reply_target_id && row.speaker != "you"
            }
          raise Errors::InvalidSelection, "Selected reply target is not an authorized incoming message."
        end
      end

      # The preview is not an authority: invalidate it on a concurrent
      # membership/consent or personal goal revision change.
      @access.authorize!(room: room.reload, actor: actor)
      # Reauthorize the exact selected sources, not only room membership.
      SourceSelection.apply!(room: room, actor: actor, bundle: selected, hint: note)
      goal = current_goal!(request, actor, room)
      plan(request, actor, room, source: "bounded_room_context",
        source_ids: selected.source_ids, prepared: selected, goal: goal)
    end

    # Capture current grants, including their revisions. Revoking and granting
    # permission again during a provider round trip must invalidate that output
    # even when the final boolean returns to 'ready'. This is metadata only:
    # no consent records or timestamps are placed in the model input.
    def consent_fingerprint(room)
      ids = room.participants.distinct.pluck(:user_id).sort
      rows = AiRoomContextConsent.where(room_id: room.id, user_id: ids).index_by(&:user_id)
      snapshot = ids.map do |id|
        record = rows[id]
        [id, record&.granted_at&.utc&.iso8601(6),
          record&.revoked_at&.utc&.iso8601(6),
          record&.updated_at&.utc&.iso8601(6)]
      end
      Digest::SHA256.hexdigest(JSON.generate(snapshot))
    end

    def current_goal!(request, actor, room)
      if request.goal_source == "room_instructions"
        return RoomInstructionGoal.load!(room: room, actor: actor,
          expected_revision: request.expected_goal_revision)
      end
      raise Errors::InvalidSelection, "Invalid goal source." unless request.goal_source.nil?
      goal = AiConversationGoal.find_by(room: room, user: actor, active: true)
      unless goal && goal.revision == request.expected_goal_revision
        raise Errors::InvalidSelection, "Personal goal is absent or stale."
      end
      goal
    end
  end
end
