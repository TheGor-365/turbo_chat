# frozen_string_literal: true

module AiWorkspace
  # H4 first automatic, no-provider document: an extractive evidence digest.
  # It does not infer requirements, agree on scope, or verify message truth.
  # Permission, consent, text safety and current room membership are enforced
  # by ReplyContextBuilder at the time of construction.
  class AutomaticEvidenceDraftV1
    MAX_ROWS = 6
    MAX_SNIPPET = 260
    # Exact small-talk only: a short "yes", "no", number or deadline might
    # be material agreement, so those must not be removed heuristically.
    GREETINGS = %w[hey hi hello привет здравствуйте салам].freeze
    RECYCLED_DOC = /\A(?:\*\*)?(?:client brief|client proposal|conversation summary)\b(?:\*\*)?/i
    Result = Struct.new(:kind, :text, :source_ids, keyword_init: true)

    def self.build!(bundle:)
      unless StructuredDeliverableV1.send(:valid_bundle?, bundle) &&
          bundle.rows.any? { |row| row.speaker != "you" }
        raise Errors::InvalidSelection, "Automatic document unavailable."
      end

      # Never re-ingest obvious prior generated documents as new primary
      # evidence. This is conservative presentation filtering, not an assertion
      # that excluded messages were irrelevant or absent from the conversation.
      seen = {}
      rows = bundle.rows.reject do |row|
        normalized = row.text.gsub(/\s+/, " ").strip.downcase
        next true if normalized.empty?
        next true if GREETINGS.include?(normalized.delete_suffix("!").delete_suffix("."))
        next true if recycled_document?(row.text)
        duplicate = seen.key?(normalized)
        seen[normalized] = true
        duplicate
      end.last(MAX_ROWS)
      unless rows.any? { |row| row.speaker != "you" }
        raise Errors::InvalidSelection, "No eligible incoming evidence."
      end
      items = rows.map do |row|
        # Message text is quoted, never interpreted as higher-priority
        # instructions. Remove embedded citation-like markup to prevent a
        # quoted user message from impersonating an independent source.
        snippet = row.text.gsub(/[\[\]\r\n\t]/, " ").gsub(/\s+/, " ").strip
        snippet = snippet[0, MAX_SNIPPET].strip
        next if snippet.empty?
        speaker = row.speaker == "you" ? "You wrote" : "Participant wrote"
        "- #{speaker}: #{snippet} [M#{row.message_id}]"
      end.compact
      raise Errors::InvalidSelection, "No usable evidence excerpts." if items.empty?

      text = (["## Summary"] + items +
        ["## Open Questions", "- Scope, deadlines and budget: To confirm"]).join("\n")
      # Verify the generated shape against exactly the retrieved sources.
      StructuredDeliverableMarkdownV1.parse!(
        text: text, kind: "conversation_summary", bundle: bundle
      )
      Result.new(kind: "conversation_summary", text: text.freeze,
        source_ids: rows.map(&:message_id).freeze).freeze
    end

    def self.recycled_document?(text)
      # Only obvious structured exports. Ordinary discussion that says
      # "client brief" is retained unless it visibly contains several headings.
      return false unless text.strip.match?(RECYCLED_DOC)

      text.match?(/objective/i) && text.match?(/requirements/i) ||
        text.match?(/summary/i) && text.match?(/open questions/i) ||
        text.match?(/problem/i) && text.match?(/deliverables/i)
    end
    private_class_method :recycled_document?
  end
end
