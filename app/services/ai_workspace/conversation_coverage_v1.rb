# frozen_string_literal: true

require "digest"

module AiWorkspace
  # Offline, consent-scoped inventory only. Not a provider authorization token,
  # stable database snapshot, or replacement for ReplyContextBuilder.
  class ConversationCoverageV1
    VERSION = 1
    MAX_MESSAGES = 10_000
    BATCH_SIZE = 200

    Report = Struct.new(:version, :room_id, :actor_id, :watermark_message_id,
      :total_messages, :scanned_author_messages, :safe_text_messages,
      :filtered_former_author, :filtered_non_text, :filtered_sensitive,
      :filtered_invalid, :filtered_withheld_author, :source_sha256, keyword_init: true)

    def initialize(access: RoomContextAccess.new, max_messages: MAX_MESSAGES)
      unless max_messages.instance_of?(Integer) && max_messages.between?(1, MAX_MESSAGES)
        raise ArgumentError, "Invalid inventory limit."
      end
      @access = access
      @max_messages = max_messages
    end

    def build(room:, actor:)
      @access.authorize!(room: room, actor: actor)
      members = room.participants.distinct.pluck(:user_id).sort.freeze
      watermark = room.messages.maximum(:id).to_i
      window = room.messages.where("messages.id <= ?", watermark)
      total = window.count
      if total > @max_messages
        raise Errors::InvalidSelection, "History exceeds the offline inventory limit."
      end

      policy = ContextAuthorPolicy.new
      grant_revision = policy.fingerprint(room: room, actor: actor)
      allowed = policy.resolve(room: room, actor: actor).allowed_author_ids
      current_count = window.where(user_id: members).count
      authorized = window.where(user_id: members & allowed)
      authorized_count = authorized.count
      counts = { safe: 0, non_text: 0, sensitive: 0, invalid: 0 }
      fingerprint = Digest::SHA256.new
      fingerprint.update("coverage-v1:#{room.id}:#{watermark}:#{members.join(',')}:#{total}\n")

      # Query loads no attachments or former-member message bodies.
      authorized.select(:id, :user_id, :body, :updated_at)
        .find_each(batch_size: BATCH_SIZE) do |message|
        fingerprint.update("#{message.id}:#{message.user_id}:#{message.updated_at.to_r}:")
        fingerprint.update(Digest::SHA256.hexdigest(message.body.to_s))
        fingerprint.update("\n")

        if message.body.blank?
          counts[:non_text] += 1
          next
        end

        begin
          normalized = Preprocessors::Text.call(message.body)
          if normalized.warnings.any?
            counts[:sensitive] += 1
          else
            counts[:safe] += 1
          end
        rescue Errors::InvalidSelection
          counts[:invalid] += 1
        end
      end

      # Revalidation closes known races without claiming transactionally
      # consistent source versions. No provider can consume this report.
      room.reload
      @access.authorize!(room: room, actor: actor)
      unless members == room.participants.distinct.pluck(:user_id).sort &&
          policy.fingerprint(room: room, actor: actor) == grant_revision &&
          watermark == room.messages.maximum(:id).to_i && total == window.count
        raise Errors::InvalidSelection, "Conversation changed during coverage inventory."
      end

      Report.new(version: VERSION, room_id: room.id, actor_id: actor.id,
        watermark_message_id: watermark, total_messages: total,
        scanned_author_messages: authorized_count,
        safe_text_messages: counts.fetch(:safe),
        filtered_former_author: total - current_count,
        filtered_withheld_author: current_count - authorized_count,
        filtered_non_text: counts.fetch(:non_text),
        filtered_sensitive: counts.fetch(:sensitive),
        filtered_invalid: counts.fetch(:invalid),
        source_sha256: fingerprint.hexdigest.freeze).freeze
    end
  end
end
