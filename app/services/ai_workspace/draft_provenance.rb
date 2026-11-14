# frozen_string_literal: true

require "digest"

module AiWorkspace
  # A short-lived attestation that an authenticated user received a real
  # own-draft xAI result in this room. It is NOT a signature on final authored
  # text: after Beautify the user may edit the suggestion before sending it.
  # No consent to room history and no automatic Send are conferred.
  class DraftProvenance
    PURPOSE = "ai-message-provenance-v1"
    TTL = 30.minutes

    def self.issue(actor:, room:, source_text:)
      raise ArgumentError, "Invalid source" unless valid_text?(source_text)
      verifier.generate({
        "v" => 1, "user" => actor.id, "room" => room.id,
        "sha256" => Digest::SHA256.hexdigest(source_text)
      }, expires_in: TTL, purpose: PURPOSE)
    end

    def self.valid?(token:, actor:, room:, source_text:)
      return false unless token.is_a?(String) && token.bytesize.between?(20, 4_000)
      return false unless valid_text?(source_text)
      payload = verifier.verified(token, purpose: PURPOSE)
      return false unless payload.is_a?(Hash) && payload["v"] == 1
      return false unless payload["user"] == actor.id && payload["room"] == room.id
      digest = Digest::SHA256.hexdigest(source_text)
      stored = payload["sha256"]
      stored.is_a?(String) && stored.bytesize == digest.bytesize &&
        ActiveSupport::SecurityUtils.secure_compare(stored, digest)
    rescue ActiveSupport::MessageVerifier::InvalidSignature, ArgumentError, TypeError
      false
    end

    def self.valid_text?(text)
      text.is_a?(String) && text.present? && text.length <= Message::MAX_BODY_LENGTH &&
        text.bytesize <= 20_000
    end
    private_class_method :valid_text?

    def self.verifier
      ActiveSupport::MessageVerifier.new(
        Rails.application.key_generator.generate_key(PURPOSE, 32),
        digest: "SHA256", serializer: JSON
      )
    end
    private_class_method :verifier
  end
end
