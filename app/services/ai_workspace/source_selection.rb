# frozen_string_literal: true

require "digest"
require "json"

module AiWorkspace
  # A short-lived, signed receipt for the exact server-approved preview.
  # A client may REDUCE the bounded set, never inject additional messages.
  # The server rebuilds and reauthorizes after every paid-click request.
  class SourceSelection
    VERSION = 1
    MAX_TOKEN_BYTES = 4_096
    TTL = 10.minutes

    class << self
      def issue(room:, actor:, bundle:, hint:)
        raise Errors::InvalidSelection, "Invalid source preview." unless valid_bundle?(bundle, room, actor)
        signer.generate(receipt(room: room, actor: actor, bundle: bundle, hint: hint), expires_in: TTL)
      end

      def apply!(room:, actor:, bundle:, hint:, source_token: nil, selected_ids: nil)
        return bundle if source_token.nil? && selected_ids.nil?

        unless source_token.is_a?(String) &&
            source_token.bytesize.between?(1, MAX_TOKEN_BYTES) &&
            valid_bundle?(bundle, room, actor) &&
            selected_ids.is_a?(Array) &&
            selected_ids.size.between?(1, ReplyContextBuilder::MAX_MESSAGES) &&
            selected_ids.all? { |id| id.instance_of?(Integer) && id.positive? } &&
            selected_ids.uniq.length == selected_ids.length
          raise Errors::InvalidSelection, "Invalid source selection."
        end

        recorded = signer.verified(source_token)
        current = receipt(room: room, actor: actor, bundle: bundle, hint: hint)
        unless recorded.is_a?(Hash) && recorded == current &&
            (selected_ids - bundle.source_ids).empty?
          raise Errors::InvalidSelection, "Source review expired or context changed."
        end

        chosen = selected_ids.to_set
        rows = bundle.rows.select { |row| chosen.include?(row.message_id) }.freeze
        # A contextual reply must still contain at least one currently present
        # participant's incoming message, not only the author's own notes.
        unless rows.any? { |row| row.speaker != "you" }
          raise Errors::InvalidSelection, "Select at least one incoming message."
        end

        ids = rows.map(&:message_id).freeze
        ReplyContextBuilder::Bundle.new(
          version: bundle.version, room_id: bundle.room_id, actor_id: bundle.actor_id,
          rows: rows, source_ids: ids, characters: rows.sum { |row| row.text.length },
          omitted: bundle.omitted + bundle.rows.length - rows.length,
          retrieval_version: bundle.retrieval_version, scanned_messages: bundle.scanned_messages,
          selection_reasons: bundle.selection_reasons.slice(*ids).freeze
        ).freeze
      rescue ActiveSupport::MessageVerifier::InvalidSignature,
        ArgumentError, TypeError
        raise Errors::InvalidSelection, "Invalid or expired source review."
      end

      private

      def signer
        Rails.application.message_verifier("ai-workspace/source-selection/v1")
      end

      def valid_bundle?(bundle, room, actor)
        bundle.is_a?(ReplyContextBuilder::Bundle) &&
          bundle.room_id == room.id && bundle.actor_id == actor.id &&
          bundle.source_ids.size.between?(1, ReplyContextBuilder::MAX_MESSAGES)
      end

      def receipt(room:, actor:, bundle:, hint:)
        # Do not put excerpts, grants or personal identifiers in the token.
        # A hash of the bounded excerpts detects edits, deletion or DLP changes.
        {
          "version" => VERSION,
          "room_id" => room.id, "actor_id" => actor.id,
          "members" => room.participants.distinct.pluck(:user_id).sort,
          "hint_sha256" => Digest::SHA256.hexdigest(ContextReplyPromptV1.validate_hint!(hint)),
          "context_sha256" => Digest::SHA256.hexdigest(
            JSON.generate([
              bundle.retrieval_version, bundle.scanned_messages, bundle.omitted,
              bundle.rows.map { |row|
                [row.message_id, row.speaker, row.text, row.truncated]
              }
            ])
          )
        }
      end
    end
  end
end
