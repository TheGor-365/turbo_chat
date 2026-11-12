# frozen_string_literal: true

module AiWorkspace
  # Strict, side-effect-free admission gate for model-authored H4 documents.
  # This is structural validation only, never a determination that model
  # claims are factually true or that any participant agreed to them.
  #
  # Call only with a fresh, room-authorized ReplyContextBuilder::Bundle.
  # The caller still owns consent/budget/revocation checks and provider costs.
  class SemanticDeliverableGateV1
    REQUIRED_SECTIONS = {
      "client_brief" => %w[objective requirements constraints deliverables acceptance_criteria open_questions],
      "client_proposal" => %w[problem approach deliverables exclusions assumptions next_steps],
      "conversation_summary" => %w[summary decisions open_questions next_steps]
    }.transform_values(&:freeze).freeze
    UNVERIFIED_AGREEMENT = /\b(?:agreed|approved|accepted|confirmed|signed off|finalized|finalised)\b|(?:согласован[а-я]*|утвержден[а-я]*|подтвержден[а-я]*)/i
    UNCERTAIN = StructuredDeliverableMarkdownV1::UNCERTAIN
    # Statements explicitly denying an agreement are not claims that an
    # agreement took place. Keep positive claims subject to human review.
    NEGATED_AGREEMENT = /\\b(?:no|not|without|never)\\s+(?:(?:explicit|formal|final|mutually)\\s+)?(?:agreed|approved|accepted|confirmed)\\b|(?:не\\s+(?:был[аио]?\\s+)?(?:согласован[а-я]*|утвержден[а-я]*|подтвержден[а-я]*)|(?:нет|без)\\s+(?:согласован[а-я]*|подтвержден[а-я]*))/i
    Result = Struct.new(:document, :warnings, :complete, keyword_init: true)

    def self.inspect!(text:, kind:, bundle:)
      required = REQUIRED_SECTIONS[kind]
      unless required
        raise Errors::InvalidSelection, "Unsupported semantic deliverable."
      end
      document = StructuredDeliverableMarkdownV1.parse!(
        text: text, kind: kind, bundle: bundle
      )
      sections = document.entries.map(&:section).uniq
      missing = required - sections
      issues = []

      document.entries.each do |entry|
        # A model's claims of "confirmed", even with a citation, are not
        # evidence of agreement. Always hold them for human review.
        if possible_agreement_claim?(entry.text)
          issues << "Possible agreement claim at item #{entry.id}; needs human confirmation."
        end
        if entry.source_ids.empty? && entry.status != "needs_confirmation"
          raise Errors::InvalidSelection, "Unsupported uncited inference."
        end
      end
      missing.each { |section| issues << "Missing section: #{section}." }

      Result.new(document: document, warnings: issues.freeze,
        complete: missing.empty? && issues.empty?).freeze
    end

    def self.possible_agreement_claim?(text)
      return false if text.match?(UNCERTAIN)

      # Evaluate each occurrence separately. 'No agreed deadline, but budget
      # approved' must still warn on the affirmative second statement.
      text.to_enum(:scan, UNVERIFIED_AGREEMENT).any? do
        match = Regexp.last_match
        prefix = text[0...match.begin(0)]
        !(prefix[-45..] || prefix).match?(NEGATED_AGREEMENT)
      end
    end
    private_class_method :possible_agreement_claim?
  end
end
