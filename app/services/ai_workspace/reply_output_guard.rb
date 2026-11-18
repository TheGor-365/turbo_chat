# frozen_string_literal: true

module AiWorkspace
  # A fail-closed, deterministic postprocessor for obvious unsupported claims.
  # It is NOT a comprehensive factuality guarantee. It blocks invented links,
  # explicit money amounts and numeric dates, and detected private identifiers.
  class ReplyOutputGuard
    URL = /https?:\/\/[^\s<>"']+/i
    PRICE = /(?:[$€₽֏]\s*\d+(?:[.,]\d+)?|\b(?:USD|EUR|RUB|AMD)\s*\d+(?:[.,]\d+)?\b)/i
    DATE = /\b20\d{2}-\d{2}-\d{2}\b|\b\d{1,2}[.\/]\d{1,2}[.\/]20\d{2}\b/

    def self.validate!(text:, bundle:, hint:)
      output = Preprocessors::Text.call(text)
      raise Errors::ProviderUnavailable, "AI output needs manual review." if output.warnings.any?
      evidence = bundle.rows.map(&:text).join(" ") + " " + hint.to_s
      [URL, PRICE, DATE].each do |pattern|
        output.text.scan(pattern).each do |claim|
          unless evidence.include?(claim)
            raise Errors::ProviderUnavailable, "AI output lacks source evidence."
          end
        end
      end
      true
    rescue Errors::InvalidSelection
      raise Errors::ProviderUnavailable, "AI output unavailable."
    end
  end
end
