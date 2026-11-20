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

    def self.issue(actor:, room:, source_text:, answer_context: nil)
      raise ArgumentError, "Invalid source" unless valid_text?(source_text)
      payload = {
        "v" => 1, "user" => actor.id, "room" => room.id,
        "sha256" => Digest::SHA256.hexdigest(canonical_source(source_text))
      }
      if answer_context
        unless answer_context.is_a?(Hash) &&
            answer_context.keys.sort == %w[fingerprint goal_revision request_id] &&
            answer_context["request_id"].is_a?(String) &&
            answer_context["request_id"].match?(LocalBudgetLedger::REQUEST_ID) &&
            answer_context["goal_revision"].is_a?(Integer) &&
            answer_context["goal_revision"].positive? &&
            answer_context["fingerprint"].is_a?(String) &&
            answer_context["fingerprint"].match?(/\A[0-9a-f]{64}\z/)
          raise ArgumentError, "Invalid AI answer provenance scope"
        end
        payload["answer_context"] = answer_context
      end
      verifier.generate(payload, expires_in: TTL, purpose: PURPOSE)
    end

    def self.valid?(token:, actor:, room:, source_text:)
      return false unless token.is_a?(String) && token.bytesize.between?(20, 4_000)
      return false unless valid_text?(source_text)
      payload = verifier.verified(token, purpose: PURPOSE)
      return false unless payload.is_a?(Hash) && payload["v"] == 1
      return false unless payload["user"] == actor.id && payload["room"] == room.id
      digest = Digest::SHA256.hexdigest(canonical_source(source_text))
      stored = payload["sha256"]
      return false unless stored.is_a?(String) && stored.bytesize == digest.bytesize &&
        ActiveSupport::SecurityUtils.secure_compare(stored, digest)
      return true unless payload.key?("answer_context")
      # Unlike own-draft Beautify, a contextual answer requires re-checking
      # the exact purpose, current members' grants, source texts and settings
      # at Send time; a once-valid signed suggestion is not perpetual access.
      context = payload["answer_context"]
      return false unless context.is_a?(Hash) &&
        context.keys.sort == %w[fingerprint goal_revision request_id] &&
        context["request_id"].is_a?(String) &&
        context["request_id"].match?(LocalBudgetLedger::REQUEST_ID) &&
        context["goal_revision"].is_a?(Integer) &&
        context["goal_revision"].positive? &&
        context["fingerprint"].is_a?(String) &&
        context["fingerprint"].match?(/\A[0-9a-f]{64}\z/)
      request = GenerationOrchestrator::Request.new(
        mode: "answer", actor: actor, room: room, draft_text: "",
        request_id: context["request_id"], confirmed: "1",
        goal_source: "room_instructions",
        expected_goal_revision: context["goal_revision"])
      plan = GenerationOrchestrator.new.prepare(request: request)
      compiled = GenerationInputContract.build!(plan: plan, request: request)
      ActiveSupport::SecurityUtils.secure_compare(
        compiled.fingerprint, context["fingerprint"])
    rescue ActiveSupport::MessageVerifier::InvalidSignature, ArgumentError, TypeError,
      Errors::Unauthorized, Errors::ConsentRequired, Errors::InvalidSelection,
      Errors::InvalidPreset, Errors::ProviderUnavailable, ActiveRecord::RecordNotFound
      false
    end

    # HTML form serialization can convert LF to CRLF on submission. Treat
    # only these two newline encodings as equivalent; edits to any other
    # content, including stray CR, still invalidate the signed source.
    def self.canonical_source(text)
      text.gsub("\r\n", "\n")
    end
    private_class_method :canonical_source

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
