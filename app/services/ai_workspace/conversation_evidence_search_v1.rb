# frozen_string_literal: true

require "digest"
require "set"

module AiWorkspace
  # FCC-2d: explicit offline search over consented, safe-text room history.
  # "Evidence" here means a version-checked original *message*, never a fact
  # checked by an independent source or a final agreement between people.
  #
  # Retrieval is lexical and speech-act tags are tentative RU/EN heuristics.
  # Never turn result IDs or text into an AI/provider payload or Send action.
  class ConversationEvidenceSearchV1
    VERSION = 1
    MAX_QUERY_CHARS = 120
    MAX_QUERY_TERMS = 8
    MAX_MATCH_CANDIDATES = 400
    MAX_RESULTS = 12
    MAX_CONFLICTS = 8
    EXCERPT_LENGTH = 240

    NEGATIVE_CUES = %w[revocation_candidate rejection_candidate].freeze
    CUE_TERMS = %w[
      согласовано утверждено подтверждаю подтверждаем принимаю принимаем
      договорились одобрено отменяем отменяю отменено отзываю отозвано
      аннулирую отклоняю возражаю предлагаю предлагаем давайте рассмотрим
      предложение вариант approved confirmed accepted agreed canceled cancelled
      revoke revoked withdraw withdrawn rejected decline declined proposal
      propose suggestion suggest
    ].to_set.freeze

    def initialize(snapshot: ConversationCoverageSnapshotV2.new)
      @snapshot = snapshot
    end

    def call(room:, actor:, query:)
      normalized_query, terms = validate_query!(query)
      before = @snapshot.build(room: room, actor: actor)
      by_id = before.sources.to_h { |source| [source.message_id, source] }

      # The candidate SQL must be constrained BEFORE loading any body:
      # current author + IDs classified safe by the fresh coverage snapshot.
      # LIKE patterns are parameterized, not interpolated into SQL.
      rows = fetch_candidates(room: room, sources: by_id, terms: terms)
      truncated = rows.size > MAX_MATCH_CANDIDATES
      rows = rows.first(MAX_MATCH_CANDIDATES)

      matches = rows.filter_map do |id, user_id, body, updated_at|
        source = by_id[id]
        next unless source && source.author_id == user_id

        normalized = Preprocessors::Text.call(body)
        raise Errors::InvalidSelection, "Source changed." if normalized.warnings.any?
        unless Digest::SHA256.hexdigest(body) == source.body_sha256 &&
            updated_at&.utc&.iso8601(6) == source.updated_at
          raise Errors::InvalidSelection, "Source changed during evidence search."
        end

        score = ContextRelevanceV2.score(normalized.text, terms: terms)
        next unless score.positive?
        {
          id: id, updated_at: source.updated_at,
          score: score,
          excerpt: excerpt(normalized.text, terms),
          classification: EvidenceSignalClassifierV1.call(normalized.text),
          topic_terms: topic_terms(normalized.text)
        }
      end
      ranked = matches.sort_by { |hit| [-hit.fetch(:score), -hit.fetch(:id)] }
      chosen = ranked.first(MAX_RESULTS)

      # Do not display a result from a stale source/grant. This second full
      # snapshot also detects changes in unselected/older message bodies.
      after = @snapshot.build(room: room, actor: actor)
      unless before.room_id == after.room_id && before.actor_id == after.actor_id &&
          before.source_sha256 == after.source_sha256 &&
          before.consent_sha256 == after.consent_sha256
        raise Errors::InvalidSelection, "Evidence history or permissions changed."
      end

      {
        version: VERSION,
        state: "local_lexical_evidence_candidates_not_ai",
        query: normalized_query,
        scope: "consented_private_room",
        source_inventory: {
          total_messages: before.total_messages,
          eligible_safe_text: before.included_text_messages,
          excluded_messages: before.total_messages - before.included_text_messages
        },
        retrieval: {
          method: "bounded_lexical",
          scanned_matching_rows: rows.size,
          max_matching_rows: MAX_MATCH_CANDIDATES,
          truncated_matching_rows: truncated,
          returned: chosen.size,
          max_results: MAX_RESULTS,
          not_an_exhaustive_semantic_search: true
        },
        results: chosen.map { |hit|
          hit.slice(:id, :updated_at, :score, :excerpt, :classification)
        },
        possible_conflicts: potential_conflicts(chosen),
        review: "all_candidates_require_human_verification"
      }.freeze
    end

    private

    def validate_query!(query)
      unless query.instance_of?(String) && query.bytesize <= 500
        raise Errors::InvalidSelection, "Invalid evidence query."
      end
      value = Preprocessors::Text.call(query)
      unless value.warnings.empty? && value.characters.between?(3, MAX_QUERY_CHARS)
        raise Errors::InvalidSelection, "Invalid evidence query."
      end
      terms = ContextRelevanceV2.terms(value.text).first(MAX_QUERY_TERMS)
      raise Errors::InvalidSelection, "No searchable query terms." if terms.empty?
      [value.text.strip.freeze, terms.freeze]
    end

    def fetch_candidates(room:, sources:, terms:)
      return [] if sources.empty?
      # Construct a trusted SQL AST instead of dynamically interpolating
      # even a generated placeholder string. PostgreSQL emits ILIKE for
      # Arel.matches(case_sensitive: false); LIKE wildcards are escaped.
      body = Message.arel_table[:body]
      clauses = terms.map do |term|
        pattern = "%#{ActiveRecord::Base.sanitize_sql_like(term)}%"
        body.matches(pattern, nil, false)
      end
      predicate = clauses.reduce { |combined, clause| combined.or(clause) }
      room.messages.where(id: sources.keys).where(predicate)
        .order(id: :desc).limit(MAX_MATCH_CANDIDATES + 1)
        .pluck(:id, :user_id, :body, :updated_at)
    end

    def excerpt(text, terms)
      downcase = text.downcase
      offsets = terms.filter_map { |term| downcase.index(term) }
      start = offsets.empty? ? 0 : [offsets.min - 64, 0].max
      start = [start, [text.length - EXCERPT_LENGTH, 0].max].min
      value = text[start, EXCERPT_LENGTH].to_s
      value = "…" + value if start.positive?
      value += "…" if start + EXCERPT_LENGTH < text.length
      value.freeze
    end

    def topic_terms(text)
      (ContextRelevanceV2.terms(text).to_set - CUE_TERMS).freeze
    end

    def potential_conflicts(results)
      # A confirmation cue can be *potentially* challenged by a later
      # revocation/rejection cue about overlapping content. Even this
      # heuristic is NOT proof the two statements refer to the same decision.
      pairs = []
      confirmed = results.select { |hit|
        hit.dig(:classification, :state) == "confirmation_candidate"
      }
      negative = results.select { |hit|
        NEGATIVE_CUES.include?(hit.dig(:classification, :state))
      }
      confirmed.each do |a|
        negative.each do |b|
          next if a[:id] == b[:id]
          overlap = a[:topic_terms] & b[:topic_terms]
          next unless overlap.size >= 2

          pairs << {
            source_ids: [a[:id], b[:id]].sort,
            state: "possible_conflict_requires_review",
            shared_topic_terms: overlap.to_a.sort.first(4)
          }
          return pairs.freeze if pairs.size >= MAX_CONFLICTS
        end
      end
      pairs.freeze
    end
  end
end
