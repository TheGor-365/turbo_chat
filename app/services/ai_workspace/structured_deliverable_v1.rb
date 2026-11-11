# frozen_string_literal: true

module AiWorkspace
  # H4 contract for ephemeral human-reviewed deliverables. It does not parse
  # free-form AI output, verify factual truth, store records or grant room access.
  class StructuredDeliverableV1
    VERSION = 1
    MAX_ITEMS = 36
    MAX_TEXT_CHARS = 600
    SECTIONS = {
      "client_brief" => %w[objective audience requirements constraints deliverables acceptance_criteria open_questions],
      "client_proposal" => %w[problem approach deliverables exclusions assumptions next_steps],
      "conversation_summary" => %w[summary decisions open_questions next_steps]
    }.transform_values(&:freeze).freeze
    DRAFT_STATUSES = %w[inferred unknown needs_confirmation].freeze
    REVIEW_DECISIONS = {
      "confirm" => "confirmed",
      "keep_inferred" => "inferred",
      "mark_unknown" => "unknown",
      "request_confirmation" => "needs_confirmation"
    }.freeze
    ENTRY_KEYS = %i[section text status source_ids].freeze

    Entry = Struct.new(:id, :section, :text, :status, :source_ids,
      :reviewed_by_actor_id, keyword_init: true)
    Document = Struct.new(:version, :kind, :room_id, :actor_id,
      :source_ids, :entries, :review_state, keyword_init: true)

    # Input is an explicit typed draft, NOT the provider's Markdown response.
    # A citation and even lexical overlap never automatically mean "confirmed".
    def self.build!(kind:, entries:, bundle:)
      sections = SECTIONS[kind]
      unless sections && entries.is_a?(Array) && entries.size.between?(1, MAX_ITEMS) &&
          valid_bundle?(bundle)
        raise Errors::InvalidSelection, "Invalid structured deliverable."
      end

      items = entries.each_with_index.map do |data, index|
        unless data.is_a?(Hash) && (data.keys - ENTRY_KEYS).empty? &&
            ENTRY_KEYS.all? { |key| data.key?(key) }
          raise Errors::InvalidSelection, "Invalid structured deliverable entry."
        end

        section, status = data.values_at(:section, :status)
        text, references = data.values_at(:text, :source_ids)
        unless sections.include?(section) && DRAFT_STATUSES.include?(status) &&
            text.is_a?(String) && text.valid_encoding? &&
            text.strip.length.between?(1, MAX_TEXT_CHARS) &&
            !text.include?("\0") && valid_sources?(references, bundle.source_ids)
          raise Errors::InvalidSelection, "Invalid structured deliverable entry."
        end

        # Inline [M...] references must be precisely present in the item's
        # permitted source list; model-supplied numbers cannot expand access.
        # Scan bounded text without a citation length cap: overlong tags and
        # unclosed [M fragments must not evade validation.
        citations = text.scan(/\[M[^\]\n]*\]/)
        unless citations.size == text.scan(/\[M/).size &&
            (status != "inferred" || references.any?)
          raise Errors::InvalidSelection, "Invalid structured deliverable citation."
        end
        citations.each do |citation|
          match = EvidenceReviewV1::REFERENCE.match(citation)
          unless match && match[0] == citation && references.include?(match[1].to_i)
            raise Errors::InvalidSelection, "Invalid structured deliverable citation."
          end
        end

        Entry.new(id: index + 1, section: section, text: text.strip.dup.freeze,
          status: status, source_ids: references.dup.freeze,
          reviewed_by_actor_id: nil).freeze
      end.freeze

      Document.new(version: VERSION, kind: kind, room_id: bundle.room_id,
        actor_id: bundle.actor_id, source_ids: bundle.source_ids.dup.freeze,
        entries: items, review_state: "pending_manual_review").freeze
    end

    # Only call from an authenticated, currently authorized room workflow.
    # This pure transition checks the originating actor but not live ACL.
    # "confirmed" means explicitly marked by this human, NOT fact-checked.
    def self.review!(document:, entry_id:, actor_id:, decision:)
      unless document.is_a?(Document) && actor_id.is_a?(Integer) &&
          actor_id.positive? && document.actor_id == actor_id
        raise Errors::Unauthorized, "Review unavailable."
      end
      new_status = REVIEW_DECISIONS[decision]
      unless new_status && entry_id.is_a?(Integer) &&
          document.entries.any? { |entry| entry.id == entry_id }
        raise Errors::InvalidSelection, "Invalid review decision."
      end

      updated = document.entries.map do |entry|
        next entry unless entry.id == entry_id

        Entry.new(id: entry.id, section: entry.section, text: entry.text,
          status: new_status, source_ids: entry.source_ids,
          reviewed_by_actor_id: actor_id).freeze
      end.freeze
      state = updated.all? { |entry| entry.reviewed_by_actor_id } ?
        "reviewed_not_approved" : "pending_manual_review"
      Document.new(version: document.version, kind: document.kind,
        room_id: document.room_id, actor_id: document.actor_id,
        source_ids: document.source_ids, entries: updated,
        review_state: state).freeze
    end

    def self.valid_bundle?(bundle)
      bundle.is_a?(ReplyContextBuilder::Bundle) &&
        bundle.room_id.is_a?(Integer) && bundle.room_id.positive? &&
        bundle.actor_id.is_a?(Integer) && bundle.actor_id.positive? &&
        bundle.rows.is_a?(Array) && bundle.source_ids.is_a?(Array) &&
        bundle.source_ids.size.between?(1, ReplyContextBuilder::MAX_MESSAGES) &&
        bundle.source_ids.uniq == bundle.source_ids &&
        bundle.source_ids.all? { |id| id.is_a?(Integer) && id.positive? } &&
        bundle.rows.map(&:message_id).sort == bundle.source_ids.sort
    end
    private_class_method :valid_bundle?

    def self.valid_sources?(references, available)
      references.is_a?(Array) &&
        references.size <= ReplyContextBuilder::MAX_MESSAGES &&
        references.uniq == references &&
        references.all? { |id| id.is_a?(Integer) && available.include?(id) }
    end
    private_class_method :valid_sources?
  end
end
