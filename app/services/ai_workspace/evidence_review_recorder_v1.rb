# frozen_string_literal: true

module AiWorkspace
  # FCC-2e.2a: one human's explicit stance regarding one original message
  # version. Never infer a group-wide decision. No LLM, notifications, Send,
  # stored message copy, or provider budget is involved.
  class EvidenceReviewRecorderV1
    VERSION = 1

    def initialize(snapshot: ConversationCoverageSnapshotV2.new)
      @snapshot = snapshot
    end

    def call(room:, actor:, message_id:, source_version:, stance:, request_key:)
      id = strict_id!(message_id)
      unless source_version.is_a?(String) &&
          source_version.match?(/\A[0-9a-f]{64}\z/) &&
          AiEvidenceReviewEvent::STANCES.include?(stance) &&
          request_key.is_a?(String) &&
          request_key.match?(AiEvidenceReviewEvent::UUID)
        raise Errors::InvalidSelection, "Invalid review request."
      end
      unless room&.is_private? && room.accessible_to?(actor)
        raise Errors::Unauthorized, "Room unavailable."
      end

      result = nil
      room.with_lock do
        before = @snapshot.build(room: room, actor: actor)
        source = before.sources.find { |entry| entry.message_id == id }
        unless source && source.version_sha256 == source_version
          raise Errors::InvalidSelection, "Source version is not current or eligible."
        end

        common = AiEvidenceReviewEvent.where(room_id: room.id,
          message_id: id, reviewer_id: actor.id)
        latest = common.order(id: :desc).first
        same_version = latest && latest.source_version_sha256 == source.version_sha256
        existing_key = AiEvidenceReviewEvent.find_by(
          reviewer_id: actor.id, request_key: request_key
        )
        if existing_key
          # Retrying the same action is safe only if it remains the latest
          # event for this participant, source, version and stance.
          unless existing_key.id == latest&.id && same_version &&
              existing_key.stance == stance
            raise Errors::InvalidSelection, "Idempotency key reused."
          end
          event = existing_key
          operation = "replayed"
        elsif stance == "withdrawn" &&
            (!same_version || latest.stance == "withdrawn")
          # A new request key cannot create a second withdrawal. Only a retry
          # with the original key (handled above) is replay-idempotent.
          raise Errors::InvalidSelection, "No active personal stance to withdraw."
        elsif same_version && latest.stance == stance
          event = latest
          operation = "unchanged"
        else
          event = AiEvidenceReviewEvent.create!(
            room: room, message_id: id, reviewer: actor,
            source_version_sha256: source.version_sha256,
            stance: stance, request_key: request_key
          )
          operation = "recorded"
        end

        # Commit fails closed on an observed concurrent message edit, member
        # departure, DLP warning or AI-context consent change. A saved review
        # is never authorization to read history after revocation.
        after = @snapshot.build(room: room, actor: actor)
        verified = after.sources.find { |entry| entry.message_id == id }
        unless before.source_sha256 == after.source_sha256 &&
            before.consent_sha256 == after.consent_sha256 &&
            verified&.version_sha256 == source.version_sha256
          raise Errors::InvalidSelection, "Review source or access changed."
        end

        result = {
          version: VERSION, state: "personal_stance_not_room_consensus",
          message_id: id, source_version: source.version_sha256,
          personal_stance: event.stance == "withdrawn" ? "none" : event.stance,
          event_id: event.id, recorded_at: event.created_at.utc.iso8601(6),
          operation: operation, room_approval_state: "not_determined"
        }.freeze
      end
      result
    end

    private

    def strict_id!(id)
      value = id.to_s
      unless (id.is_a?(String) || id.instance_of?(Integer)) &&
          value.match?(/\A[1-9]\d{0,17}\z/)
        raise Errors::InvalidSelection, "Invalid message reference."
      end
      value.to_i
    end
  end
end
