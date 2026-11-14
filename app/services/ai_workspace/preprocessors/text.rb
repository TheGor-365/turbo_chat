# frozen_string_literal: true

module AiWorkspace
  module Preprocessors
    # Deliberately conservative: normalize line endings and Unicode NFC,
    # never rewrite code blocks, links, quotes or Markdown hard line breaks.
    # Indicators are metadata flags, not extracted PII/secret values.
    class Text
      MAX_CHARACTERS = 5_000
      MAX_BYTES = 20_000
      Result = Struct.new(:text, :characters, :warnings, keyword_init: true)
      EMAIL = /\b[A-Z0-9._%+\-]+@[A-Z0-9.\-]+\.[A-Z]{2,}\b/i
      TOKEN = /\b(?:sk-(?:proj-)?[A-Za-z0-9_-]{16,}|gh[pousr]_[A-Za-z0-9]{16,}|AIza[A-Za-z0-9_-]{24,})\b/
      FORBIDDEN_CONTROL = /[\x00-\x08\x0B\x0C\x0E-\x1F\x7F]/

      def self.call(source)
        unless source.instance_of?(String) && source.bytesize <= MAX_BYTES && source.valid_encoding?
          raise Errors::InvalidSelection, "Invalid or oversized text."
        end
        normalized = source.encode(Encoding::UTF_8).gsub(/\r\n?/, "\n").unicode_normalize(:nfc)
        if normalized.match?(FORBIDDEN_CONTROL) || normalized.strip.empty? || normalized.length > MAX_CHARACTERS
          raise Errors::InvalidSelection, "Invalid or oversized text."
        end

        warnings = []
        warnings << :possible_email if normalized.match?(EMAIL)
        warnings << :possible_secret if normalized.match?(TOKEN)
        Result.new(text: normalized.freeze, characters: normalized.length, warnings: warnings.freeze).freeze
      rescue EncodingError, ArgumentError
        raise Errors::InvalidSelection, "Invalid or oversized text."
      end
    end
  end
end
