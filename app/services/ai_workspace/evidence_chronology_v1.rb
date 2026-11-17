# frozen_string_literal: true

module AiWorkspace
  # FCC-2e.1: chronology of the ALREADY SELECTED version-checked source
  # candidates. Ordering is by persisted message creation time and ID.
  #
  # Linking two messages by lexical topic overlap cannot prove that either
  # person accepted, rescinded or even discussed the same exact term.
  # All relationships are candidate leads for explicit HUMAN inspection.
  class EvidenceChronologyV1
    VERSION = 1
    MAX_EVENTS = ConversationEvidenceSearchV1::MAX_RESULTS
    MAX_LINKS = 8
    MIN_SHARED_TERMS = 2

    CONFIRM = "confirmation_candidate"
    PROPOSAL = "proposal"
    NEGATIVE = %w[revocation_candidate rejection_candidate].freeze

    def self.call(selected:)
      unless selected.is_a?(Array) && selected.size <= MAX_EVENTS &&
          selected.all? { |hit| valid_hit?(hit) }
        raise Errors::InvalidSelection, "Invalid chronology sources."
      end

      ordered = selected.sort_by { |hit| [hit.fetch(:created_at), hit.fetch(:id)] }
      links = []
      ordered.each_with_index do |newer, index|
        # Search the nearest EARLIER event only; matching terms are not the
        # same thing as resolving a claim, entity, negation scope or contract.
        ordered.first(index).reverse_each do |older|
          relation = relation(older.dig(:classification, :state),
            newer.dig(:classification, :state))
          next unless relation

          overlap = (older.fetch(:topic_terms) & newer.fetch(:topic_terms)).to_a.sort
          next if overlap.size < MIN_SHARED_TERMS

          links << {
            earlier_id: older.fetch(:id), later_id: newer.fetch(:id),
            relation: relation, shared_terms: overlap.first(4),
            certainty: "lexical_candidate_only"
          }
          break
        end
        break if links.size >= MAX_LINKS
      end

      {
        version: VERSION,
        state: "unverified_candidate_chronology",
        scope: "selected_ranked_matches_only",
        order_by: "message_created_at_utc_then_id",
        events: ordered.map { |hit|
          {
            id: hit.fetch(:id), created_at: hit.fetch(:created_at),
            speaker: hit.fetch(:speaker),
            cue: hit.fetch(:classification).fetch(:state)
          }
        },
        links: links,
        approval_state: "not_determined",
        requires_human_review: true
      }.freeze
    end

    def self.valid_hit?(hit)
      hit.is_a?(Hash) && hit[:id].instance_of?(Integer) &&
        hit[:id].positive? && hit[:created_at].is_a?(String) &&
        hit[:created_at].match?(/\A\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}/) &&
        hit[:speaker].is_a?(String) &&
        (hit[:speaker] == "you" || hit[:speaker].match?(/\Aparticipant_[1-9]\d?\z/)) &&
        hit[:classification].is_a?(Hash) &&
        hit[:classification][:state].is_a?(String) &&
        hit[:topic_terms].respond_to?(:&) && hit[:topic_terms].respond_to?(:to_a)
    end
    private_class_method :valid_hit?

    def self.relation(older, newer)
      case [older, newer]
      when [PROPOSAL, CONFIRM]
        "possible_response_to_proposal"
      when [CONFIRM, *NEGATIVE]
        # Array pattern interpolation is not an enum; handle negatives below.
        "possible_reversal"
      else
        return "possible_reversal" if older == CONFIRM && NEGATIVE.include?(newer)
        return "possible_reconfirmation" if NEGATIVE.include?(older) && newer == CONFIRM
        nil
      end
    end
    private_class_method :relation
  end
end
