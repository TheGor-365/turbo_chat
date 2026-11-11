# frozen_string_literal: true

module AiWorkspace
  # Conservative, offline adapter for human-readable contextual task output.
  # Not a semantic fact checker and never an approval/publishing path.
  class StructuredDeliverableMarkdownV1
    MAX_LINES = 160
    MAX_LINE_CHARS = 600
    HEADINGS = {
      "client_brief" => {
        "objective" => "objective", "audience" => "audience",
        "requirements" => "requirements", "constraints" => "constraints",
        "deliverables" => "deliverables", "acceptance criteria" => "acceptance_criteria",
        "open questions" => "open_questions"
      },
      "client_proposal" => {
        "problem" => "problem", "approach" => "approach",
        "proposed work" => "approach", "deliverables" => "deliverables",
        "exclusions" => "exclusions", "assumptions" => "assumptions",
        "next steps" => "next_steps"
      },
      "conversation_summary" => {
        "summary" => "summary", "confirmed facts" => "summary",
        "decisions" => "decisions", "open questions" => "open_questions",
        "next steps" => "next_steps"
      }
    }.transform_values(&:freeze).freeze
    UNCERTAIN = /\b(?:to confirm|tbd|unknown|needs confirmation)\b|(?:нужно уточнить|требует уточнения|не подтверждено|уточнить)/i
    CITATION_FRAGMENT = /\[M/

    def self.parse!(text:, kind:, bundle:)
      headings = HEADINGS[kind]
      unless headings && text.is_a?(String) && text.valid_encoding? &&
          text.length.between?(1, 5_000)
        raise Errors::InvalidSelection, "Invalid structured source."
      end
      lines = text.gsub(/\r\n?/, "\n").split("\n")
      if lines.size > MAX_LINES || lines.any? { |line| line.length > MAX_LINE_CHARS }
        raise Errors::InvalidSelection, "Structured source exceeds limits."
      end

      section = nil
      entries = []
      meaningful_lines = lines.map(&:strip).reject(&:empty?)
      # Human-visible legacy task outputs often start with a plain document title.
      # Only a single known title is ignored, and only before the first section.
      titles = {
        "client_brief" => "client brief",
        "client_proposal" => "client proposal",
        "conversation_summary" => "conversation summary"
      }
      meaningful_lines.each_with_index do |line, index|
        # No speculative interpretation of code, tables, quotes or headings.
        if line.start_with?("```", "~~~", "|", ">") || line.match?(/\A(?:\#){4,6}\s/)
          raise Errors::InvalidSelection, "Unsupported structured source format."
        end
        label = line.sub(/\A(?:\#){1,3}\s+/, "")
          .sub(/\A\*\*(.+)\*\*\z/, '\1')
          .sub(/:\z/, "").strip.downcase
        if index.zero? && label == titles[kind]
          next
        end
        if headings.key?(label)
          section = headings.fetch(label)
          next
        end
        # A marked heading must be a supported section; never ingest
        # an unknown heading as a claim by accident.
        if line.match?(/\A(?:\#){1,3}\s+/) ||
            line.match?(/\A\*\*[^*]+\*\*\z/)
          raise Errors::InvalidSelection, "Unknown structured section."
        end
        unless section
          raise Errors::InvalidSelection, "Structured content requires a known section."
        end
        # Preserve paragraphs from legacy client briefs and standard lists.
        # Each nonblank line is an independent, never-confirmed statement.
        claim = line.sub(/\A(?:[-*•]\s+|\d+[.)]\s+)/, "").strip
        raise Errors::InvalidSelection, "Empty structured item." if claim.empty?

        tokens = claim.scan(/\[M[^\]\n]*\]/)
        if tokens.length != claim.scan(CITATION_FRAGMENT).length
          raise Errors::InvalidSelection, "Malformed structured source citation."
        end
        ids = tokens.map do |token|
          match = EvidenceReviewV1::REFERENCE.match(token)
          unless match && match[0] == token
            raise Errors::InvalidSelection, "Malformed structured source citation."
          end
          match[1].to_i
        end.uniq
        status = if claim.match?(UNCERTAIN)
          "needs_confirmation"
        elsif ids.empty?
          "needs_confirmation"
        else
          "inferred"
        end
        entries << { section: section, text: claim, status: status, source_ids: ids }
      end
      StructuredDeliverableV1.build!(kind: kind, entries: entries, bundle: bundle)
    end
  end
end
