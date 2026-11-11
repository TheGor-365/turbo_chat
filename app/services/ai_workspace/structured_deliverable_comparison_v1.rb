# frozen_string_literal: true

module AiWorkspace
  # H4: exact, occurrence-aware comparison of two separately validated typed
  # drafts. "Added" and "removed" do not imply a semantic edit or approval.
  # The service is pure: no persistence, provider calls, or ACL grants.
  class StructuredDeliverableComparisonV1
    Result = Struct.new(:unchanged, :removed, :added, keyword_init: true)

    def self.compare!(original:, proposed:)
      unless original.is_a?(StructuredDeliverableV1::Document) &&
          proposed.is_a?(StructuredDeliverableV1::Document) &&
          original.version == proposed.version &&
          original.kind == proposed.kind &&
          original.room_id == proposed.room_id &&
          original.actor_id == proposed.actor_id &&
          original.source_ids == proposed.source_ids
        raise Errors::InvalidSelection, "Document comparison unavailable."
      end

      available = Hash.new(0)
      proposed.entries.each { |entry| available[key(entry)] += 1 }

      unchanged = []
      removed = []
      original.entries.each do |entry|
        signature = key(entry)
        if available[signature].positive?
          unchanged << entry
          available[signature] -= 1
        else
          removed << entry
        end
      end

      original_counts = Hash.new(0)
      original.entries.each { |entry| original_counts[key(entry)] += 1 }
      added = []
      proposed.entries.each do |entry|
        signature = key(entry)
        if original_counts[signature].positive?
          original_counts[signature] -= 1
        else
          added << entry
        end
      end

      Result.new(unchanged: unchanged.freeze, removed: removed.freeze,
        added: added.freeze).freeze
    end

    def self.key(entry)
      [entry.section, entry.text, entry.source_ids].freeze
    end
    private_class_method :key
  end
end
