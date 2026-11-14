# frozen_string_literal: true

module AiWorkspace
  # Offline reference-structure check, never semantic fact verification.
  # No provider calls, stored drafts or source text in the report.
  class EvidenceReviewV1
    VERSION = 1
    REFERENCE = /\[M([1-9]\d{0,17})\]/
    CANDIDATE = /\[M[^\]\n]{0,30}\]/
    UNKNOWN = /\b(?:to confirm|tbd|unknown|needs confirmation)\b|(?:нужно уточнить|требует уточнения|не подтверждено|уточнить)|(?:հստակեցնել|հաստատել)/i

    def self.inspect!(text:, bundle:)
      unless text.is_a?(String) && text.valid_encoding? &&
          text.length.between?(1, 5_000) &&
          bundle.is_a?(ReplyContextBuilder::Bundle) &&
          bundle.rows.is_a?(Array) && bundle.source_ids.is_a?(Array) &&
          bundle.source_ids.size.between?(1, ReplyContextBuilder::MAX_MESSAGES) &&
          bundle.source_ids.uniq == bundle.source_ids
        raise Errors::ProviderUnavailable, "AI evidence review unavailable."
      end
      in_code = false
      prose = []
      text.gsub(/\r\n?/, "\n").split("\n", -1).each_with_index do |raw, index|
        line = raw.strip
        if line.start_with?(96.chr * 3)
          in_code = !in_code
          next
        end
        prose << [line, index + 1] unless in_code
      end
      refs = prose.flat_map { |line, _| line.scan(CANDIDATE) }.map do |citation|
        match = REFERENCE.match(citation)
        unless match && match[0] == citation &&
            bundle.source_ids.include?(match[1].to_i)
          raise Errors::ProviderUnavailable, "AI output cites invalid source."
        end
        match[1].to_i
      end.uniq
      by_id = bundle.rows.index_by(&:message_id)
      unless refs.all? { |id| by_id.key?(id) }
        raise Errors::ProviderUnavailable, "AI output cites unknown source."
      end

      checked = linked = uncited = weak = unknown = 0
      issues = []
      prose.first(160).each do |line, line_number|
        next if line.empty? || line.match?(/\A[#]{1,6}\s/) ||
          line.match?(/\A[-*_]{3,}\z/)
        checked += 1
        ids = line.scan(REFERENCE).flatten.map(&:to_i).uniq
        if line.match?(UNKNOWN)
          unknown += 1
          issues << { line: line_number, signal: "needs_confirmation" } if issues.size < 20
        end
        if ids.empty?
          unless line.end_with?("?") || line.end_with?("؟")
            uncited += 1
            issues << { line: line_number, signal: "no_citation" } if issues.size < 20
          end
        else
          linked += 1
          terms = ContextRelevanceV2.terms(line.gsub(REFERENCE, ""))
          source_text = ids.filter_map { |id| by_id[id]&.text }.join(" ")
          if terms.any? && ContextRelevanceV2.score(source_text, terms: terms).zero?
            weak += 1
            issues << { line: line_number, signal: "weak_lexical_overlap" } if issues.size < 20
          end
        end
      end
      {
        version: VERSION, assessment: "structural_only_not_fact_checked",
        checked_lines: checked, linked_lines: linked, uncited_lines: uncited,
        weak_overlap_lines: weak, needs_confirmation_lines: unknown,
        cited_source_ids: refs.sort.freeze, truncated: prose.size > 160,
        issues: issues.freeze
      }.freeze
    end
  end
end
