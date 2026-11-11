# frozen_string_literal: true

module AiWorkspace
  # H4: deterministic, citation-first client brief. It reports what people
  # said; it does NOT infer acceptance, budgets, specifications or agreements.
  # Safe source selection is delegated to AutomaticEvidenceDraftV1.
  class AutomaticClientBriefV1
    MAX_REQUIREMENTS = 3
    MAX_QUESTIONS = 2
    Result = Struct.new(:kind, :text, :source_ids, keyword_init: true)

    def self.build!(bundle:)
      evidence = AutomaticEvidenceDraftV1.build!(bundle: bundle)
      rows = bundle.rows.select { |row| evidence.source_ids.include?(row.message_id) }
      statements, questions = rows.partition { |row| !row.text.strip.end_with?("?") }
      unless statements.any?
        raise Errors::InvalidSelection, "No explicit task statement available."
      end

      # This is an attributed extraction, not a semantic summary. Choosing
      # the newest non-question does not make the claim true or approved.
      objective = statements.last
      requirements = statements.last(MAX_REQUIREMENTS)
      questions = questions.last(MAX_QUESTIONS)
      chunks = [
        "## Objective",
        bullet("Reported task (not agreed)", objective),
        "## Requirements",
        *requirements.map { |row| bullet("Reported request (not agreed)", row) },
        "## Constraints",
        "- Technical and contractual constraints: To confirm",
        "## Deliverables",
        "- Exact deliverables and exclusions: To confirm",
        "## Acceptance Criteria",
        "- Testable acceptance criteria: To confirm",
        "## Open Questions",
        *questions.map { |row| bullet("Participant question", row) },
        "- Budget and deadline: To confirm"
      ]

      text = chunks.join("\n").freeze
      StructuredDeliverableMarkdownV1.parse!(text: text, kind: "client_brief",
        bundle: bundle)
      Result.new(kind: "client_brief", text: text,
        source_ids: ([objective] + requirements + questions).map(&:message_id).uniq.freeze).freeze
    end

    def self.bullet(label, row)
      # Keep the same conservative quoting policy as evidence digest.
      snippet = row.text.gsub(/[\[\]\r\n\t]/, " ").gsub(/\s+/, " ").strip
      snippet = snippet[0, AutomaticEvidenceDraftV1::MAX_SNIPPET].strip
      "- #{label}: #{snippet} [M#{row.message_id}]"
    end
    private_class_method :bullet
  end
end
