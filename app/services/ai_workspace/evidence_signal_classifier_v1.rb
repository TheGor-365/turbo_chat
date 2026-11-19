# frozen_string_literal: true

module AiWorkspace
  # FCC-2d: offline *candidate* speech-act cues, not an LLM, a contract
  # parser, a verified decision, or an approval by any participant.
  #
  # Quotation, sarcasm, indirect speech and topic identity cannot be resolved
  # here. Never promote these cues to "confirmed" without human review.
  class EvidenceSignalClassifierV1
    VERSION = 1

    REJECTION = /(?:\b(?:not\s+(?:approved|accepted|agreed|confirmed)|reject(?:ed)?|declin(?:e|ed))\b|(?<![\p{L}])(?:не\s+(?:согласен|согласна|согласовано|утверждено|подтверждаю|подтверждаем|принимаю|принимаем)|отклоняю|возражаю)(?![\p{L}]))/iu
    REVOCATION = /(?:\b(?:cancel(?:ed|led)?|withdraw(?:n)?|revok(?:e|ed)|rescinded)\b|(?<![\p{L}])(?:отменяю|отменяем|отменено|отзываю|отозвано|аннулирую)(?![\p{L}]))/iu
    CONFIRMATION = /(?:\b(?:approved|confirmed|accepted|agreed|we\s+agree|sign(?:ed)?\s+off)\b|(?<![\p{L}])(?:согласовано|утверждено|подтверждаю|подтверждаем|принимаю|принимаем|договорились|одобрено)(?![\p{L}]))/iu
    PROPOSAL = /(?:\b(?:i\s+propose|we\s+propose|let'?s\s+consider|suggest(?:ion)?|proposal|could\s+we)\b|(?<![\p{L}])(?:предлагаю|предлагаем|давайте|предложение|рассмотрим|вариант)(?![\p{L}]))/iu

    CUES = %w[proposal confirmation_candidate revocation_candidate rejection_candidate].freeze

    def self.call(text)
      unless text.instance_of?(String)
        raise Errors::InvalidSelection, "Invalid evidence text."
      end
      normalized = text.unicode_normalize(:nfc).downcase
      rejected = normalized.match?(REJECTION)
      revoked = normalized.match?(REVOCATION)
      # Negations must not themselves trigger a positive confirmation.
      positive_text = normalized.gsub(REJECTION, " ").gsub(REVOCATION, " ")
      confirmed = positive_text.match?(CONFIRMATION)
      proposed = positive_text.match?(PROPOSAL)
      cues = []
      cues << "proposal" if proposed
      cues << "confirmation_candidate" if confirmed
      cues << "revocation_candidate" if revoked
      cues << "rejection_candidate" if rejected

      # Both positive and negative phrases in one message require a reader;
      # multiple unrelated approvals in one body are not split into claims.
      status = if cues.empty?
        "undetermined"
      elsif cues.size > 1
        "mixed_requires_review"
      else
        cues.first
      end
      { state: status, cues: cues.freeze, confidence: "rule_only_unverified" }.freeze
    end
  end
end
