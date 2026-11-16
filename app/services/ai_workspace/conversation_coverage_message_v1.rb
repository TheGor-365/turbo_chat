# frozen_string_literal: true

module AiWorkspace
  # FCC-2c.1: inspect one already-eligible, current-room message after a
  # fresh unanimous-consent and full-history DLP recheck. The inventory ID is
  # a locator, never a grant. The payload never goes to an AI provider.
  class ConversationCoverageMessageV1
    VERSION = 1

    def initialize(snapshot: ConversationCoverageSnapshotV2.new)
      @snapshot = snapshot
    end

    def call(room:, actor:, message_id:)
      unless message_id.is_a?(String) && message_id.match?(/\A[1-9]\d{0,17}\z/)
        raise Errors::InvalidSelection, "Invalid message reference."
      end
      id = message_id.to_i
      before = @snapshot.build(room: room, actor: actor)
      source = before.sources.find { |candidate| candidate.message_id == id }
      raise Errors::InvalidSelection, "Source is not eligible." unless source

      # Read only the eligible row, never attachments or bodies of excluded
      # authors. Recheck actual body hash, not updated_at alone.
      row = room.messages.where(id: id, user_id: source.author_id)
        .pick(:body, :updated_at)
      raise Errors::InvalidSelection, "Source changed." unless row

      body, updated_at = row
      normalized = Preprocessors::Text.call(body)
      if normalized.warnings.any? ||
          Digest::SHA256.hexdigest(body) != source.body_sha256 ||
          updated_at&.utc&.iso8601(6) != source.updated_at
        raise Errors::InvalidSelection, "Source changed or is sensitive."
      end

      # Revalidate *after* loading text, so a concurrent consent change,
      # membership change or update invalidates the response.
      after = @snapshot.build(room: room, actor: actor)
      latest = after.sources.find { |candidate| candidate.message_id == id }
      unless before.source_sha256 == after.source_sha256 &&
          before.consent_sha256 == after.consent_sha256 &&
          latest&.version_sha256 == source.version_sha256
        raise Errors::InvalidSelection, "Source or permissions changed."
      end

      {
        version: VERSION, state: "local_review_only",
        message_id: id, updated_at: source.updated_at,
        text: normalized.text
      }.freeze
    end
  end
end
