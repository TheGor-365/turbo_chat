# frozen_string_literal: true

module AiWorkspace
  # H3g.1: bounded, deterministic retrieval with recent conversation anchors
  # and older keyword-matched evidence. PostgreSQL remains source of truth.
  # Never treat lexical matches as factual verification or full-history RAG.
  class ReplyContextBuilder
    VERSION = 1 # Provider input contract unchanged.
    RETRIEVAL_VERSION = 2
    CANDIDATE_LIMIT = 240
    RECENT_ANCHORS = 3
    HISTORICAL_HITS = 3
    MAX_MESSAGES = 9
    MAX_MESSAGE_CHARS = 420
    MAX_CONTEXT_CHARS = 2_400

    Row = Struct.new(:message_id, :speaker, :text, :truncated, keyword_init: true)
    Bundle = Struct.new(:version, :room_id, :actor_id, :rows,
      :source_ids, :characters, :omitted, :retrieval_version,
      :scanned_messages, keyword_init: true)

    def initialize(access: RoomContextAccess.new)
      @access = access
    end

    # A validated note can refine old-context retrieval without granting
    # additional access. The service re-runs this builder after budget reserve.
    def build(room:, actor:, hint: nil)
      @access.authorize!(room: room, actor: actor)
      member_ids = room.participants.distinct.pluck(:user_id).sort
      raise Errors::Unauthorized, "Conversation unavailable." unless member_ids.include?(actor.id)

      note = ContextReplyPromptV1.validate_hint!(hint)
      # Query is bounded to this room and currently participating authors.
      # No attachment associations, blobs, files or messages from other rooms.
      candidates = room.messages.where(user_id: member_ids)
        .where("NULLIF(BTRIM(messages.body), '') IS NOT NULL")
        .order(created_at: :desc, id: :desc)
        .limit(CANDIDATE_LIMIT)
        .select(:id, :room_id, :user_id, :body, :created_at).to_a

      # DLP checks the WHOLE source before truncation; never seed relevance
      # from a private address/token or include a flagged message.
      safe = candidates.filter_map do |message|
        begin
          normalized = Preprocessors::Text.call(message.body)
          next if normalized.warnings.any?
          original = normalized.text.strip
          next if original.empty?
          { id: message.id, user_id: message.user_id,
            at: message.created_at, text: original.freeze }.freeze
        rescue Errors::InvalidSelection
          nil
        end
      end
      latest_incoming = safe.find { |item| item[:user_id] != actor.id }
      unless latest_incoming
        raise Errors::InvalidSelection, "No usable incoming message in the permitted context."
      end

      # Keep latest incoming request and adjacent turns; rank older excerpts
      # by meaningful Unicode word overlap with this turn and author note.
      anchors = (safe.first(RECENT_ANCHORS) + [latest_incoming]).uniq { |item| item[:id] }
      query = [note, latest_incoming[:text],
        *safe.first(RECENT_ANCHORS).map { |item| item[:text] }].join(" ")
      terms = ContextRelevanceV2.terms(query)
      anchor_ids = anchors.map { |item| item[:id] }
      historical = safe.reject { |item| anchor_ids.include?(item[:id]) }
        .map { |item| [item, ContextRelevanceV2.score(item[:text], terms: terms)] }
        .select { |_item, score| score.positive? }
        .sort_by { |item, score| [-score, -item[:at].to_f, -item[:id]] }
        .first(HISTORICAL_HITS).map(&:first)

      selected_ids = (anchors + historical).map { |item| item[:id] }
      remaining = safe.reject { |item| selected_ids.include?(item[:id]) }
      priority = (anchors + historical + remaining).uniq { |item| item[:id] }

      used = 0
      rows = []
      priority.each do |item|
        break if rows.size >= MAX_MESSAGES || used >= MAX_CONTEXT_CHARS
        remaining_chars = MAX_CONTEXT_CHARS - used
        content = item[:text][0, [MAX_MESSAGE_CHARS, remaining_chars].min]
        next if content.empty?
        speaker = item[:user_id] == actor.id ? "you" :
          "participant_#{member_ids.index(item[:user_id]) + 1}"
        rows << Row.new(message_id: item[:id], speaker: speaker,
          text: content.freeze, truncated: content.length < item[:text].length).freeze
        used += content.length
      end
      time_by_id = safe.to_h { |item| [item[:id], item[:at]] }
      rows.sort_by! { |row| [time_by_id.fetch(row.message_id), row.message_id] }

      # "Omitted" means omitted among scanned candidates, NOT full history.
      Bundle.new(version: VERSION, room_id: room.id, actor_id: actor.id,
        rows: rows.freeze, source_ids: rows.map(&:message_id).freeze,
        characters: used, omitted: candidates.size - rows.size,
        retrieval_version: RETRIEVAL_VERSION,
        scanned_messages: candidates.size).freeze
    end
  end
end
