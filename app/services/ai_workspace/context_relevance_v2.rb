# frozen_string_literal: true

require "set"

module AiWorkspace
  # Pure, offline lexical relevance. No model call, external search or index.
  # Exact Unicode word matches prevent fuzzy accidental associations.
  class ContextRelevanceV2
    MAX_TERMS = 14
    MAX_TOKEN_LENGTH = 40
    WORD = /[\p{L}\p{N}][\p{L}\p{N}\p{M}_-]{2,}/u
    STOP = %w[
      the and for from that this with have will you your our are was were
      can could would should about please thanks thank just want need there review
      they them then into also what when where which like been more some
      мне тебя тебе меня нас вам вас это этот этих этой чтобы также
      если когда после перед потом тогда только можно нужно надо будет
      есть было были быть или для как про они она оно его её ваши
      здравствуйте привет добрый спасибо пожалуйста
      hola gracias buenos buenas favor puedes pueden usted ustedes nosotros
      este esta estos estas eso esos para como pero sobre entre desde hasta
      también igualmente gracias saludos por favor necesitar quisiera queremos
      բարեւ բարև շնորհակալություն խնդրում խնդրանք ձեզ ձեր մեր այս այդ
      մասին համար հետո առաջ ինչպես կարող նույնպես նաև հետ
      բարեհաջող ողջույն ողջույններ
    ].to_set.freeze

    def self.terms(text)
      return [] unless text.is_a?(String)

      text.downcase.scan(WORD)
        .reject { |word| word.length > MAX_TOKEN_LENGTH || STOP.include?(word) ||
          word.match?(/\A\d+\z/) }
        .uniq.first(MAX_TERMS)
    end

    def self.score(text, terms:)
      return 0 if terms.empty?
      words = text.to_s.downcase.scan(WORD).first(180).to_set
      (terms & words.to_a).size
    end
  end
end
