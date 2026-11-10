# frozen_string_literal: true

module AiWorkspace
  # Deterministic, bounded retrieval of authorized room text. No cross-room
  # search, uploads, blobs, system prompts, background indexing or embeddings.
  # This is a small, reviewable v1 retrieval algorithm, NOT full-history RAG.
  class ReplyContextBuilder
    VERSION = 1
    CANDIDATE_LIMIT = 24
    MAX_MESSAGES = 9
    MAX_MESSAGE_CHARS = 420
    MAX_CONTEXT_CHARS = 2_400

    Row = Struct.new(:message_id, :speaker, :text, :truncated, keyword_init: true)
    Bundle = Struct.new(:version, :room_id, :actor_id, :rows,
      :source_ids, :characters, :omitted, keyword_init: true)

    def initialize(access: RoomContextAccess.new)
      @access = access
    end

    def build(room:, actor:)
      @access.authorize!(room: room, actor: actor)
      member_ids = room.participants.distinct.pluck(:user_id).sort
      raise Errors::Unauthorized, "Conversation unavailable." unless member_ids.include?(actor.id)

      # Only currently participating authors. A departed user's older content
      # is never silently licensed by the remaining members' consent.
      candidates = room.messages.where(user_id: member_ids)
        .where.not(body: [nil, ""])
        .order(created_at: :desc, id: :desc)
        .limit(CANDIDATE_LIMIT)
        .select(:id, :room_id, :user_id, :body, :created_at).to_a

      rows = []
      omitted = 0
      used = 0
      candidates.each do |message|
        if rows.length >= MAX_MESSAGES || used >= MAX_CONTEXT_CHARS
          omitted += 1
          next
        end
        raw = message.body.to_s
        begin
          normalized = Preprocessors::Text.call(raw)
        rescue Errors::InvalidSelection
          omitted += 1
          next
        end
        # Conservative DLP exclusion, without leaking flagged values to
        # logs or users. This is heuristic and never claims complete safety.
        if normalized.warnings.any?
          omitted += 1
          next
        end
        remaining = MAX_CONTEXT_CHARS - used
        text = normalized.text.strip[0, [MAX_MESSAGE_CHARS, remaining].min]
        if text.empty?
          omitted += 1
          next
        end
        speaker = message.user_id == actor.id ? "you" : "participant_#{member_ids.index(message.user_id) + 1}"
        rows << Row.new(message_id: message.id, speaker: speaker,
          text: text.freeze, truncated: text.length < normalized.text.strip.length).freeze
        used += text.length
      end
      rows.reverse!
      # A reply needs some inbound evidence. Do not spend money to guess when
      # there is no usable message from another current participant.
      unless rows.any? { |row| row.speaker != "you" }
        raise Errors::InvalidSelection, "No usable incoming message in the permitted context."
      end

      Bundle.new(version: VERSION, room_id: room.id, actor_id: actor.id,
        rows: rows.freeze, source_ids: rows.map(&:message_id).freeze,
        characters: used, omitted: omitted).freeze
    end
  end
end
