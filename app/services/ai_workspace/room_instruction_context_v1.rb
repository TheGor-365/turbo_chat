# frozen_string_literal: true

require "digest"

module AiWorkspace
  # Opt-in, bounded room instructions as LOW-TRUST preference data.
  # A shared room instruction does NOT grant access to room history,
  # consent to paid inference, permission to send, or provider tools.
  class RoomInstructionContextV1
    MAX_CHARS = 1_200
    MAX_BYTES = 4_800
    Snapshot = Struct.new(:room_id, :revision_number, :text, :sha256,
      keyword_init: true) do
      def public_snapshot
        { revision_number: revision_number, text: text, characters: text.length,
          scope: "low_trust_user_preference_not_evidence" }
      end
    end

    def self.opted_in!(value)
      return false if value.nil? || value == "0"
      return true if value == "1"
      raise Errors::InvalidSelection, "Invalid room instruction opt-in."
    end

    def self.load!(room:, actor:)
      raise Errors::Unauthorized, "Room not accessible." unless
        room&.is_private? && room.accessible_to?(actor)
      revision = RoomAiInstructionRevision.where(room_id: room.id)
        .order(revision_number: :desc).first
      raise Errors::InvalidSelection, "No saved room instruction." unless
        revision&.content.present?
      content = revision.content
      raise Errors::InvalidSelection, "Room instruction exceeds AI limit." unless
        content.valid_encoding? && content.length <= MAX_CHARS &&
        content.bytesize <= MAX_BYTES
      parsed = Preprocessors::Text.call(content)
      raise Errors::InvalidSelection, "Sensitive room instruction." unless
        parsed.warnings.empty? && parsed.text == content &&
        !content.match?(RoomAiInstructionRevision::INVALID_CONTROLS) &&
        !content.match?(RoomAiInstructionRevision::POSSIBLE_SECRET)
      Snapshot.new(room_id: room.id, revision_number: revision.revision_number,
        text: content.freeze, sha256: Digest::SHA256.hexdigest(content).freeze).freeze
    end

    def self.valid_for_bundle?(snapshot, bundle)
      return true if snapshot.nil?
      snapshot.is_a?(Snapshot) && snapshot.room_id == bundle.room_id &&
        snapshot.revision_number.is_a?(Integer) && snapshot.revision_number.positive? &&
        snapshot.text.is_a?(String) && snapshot.text.length.between?(1, MAX_CHARS) &&
        snapshot.text.bytesize <= MAX_BYTES &&
        snapshot.sha256 == Digest::SHA256.hexdigest(snapshot.text)
    end
  end
end
