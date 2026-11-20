# frozen_string_literal: true

require "json"

module AiWorkspace
  # Deterministic browser-acceptance fixture. This is NOT a language model.
  # Its only purpose is to exercise the real consent/goal/provenance/Send
  # pipeline in development without network or usage-ledger side effects.
  class SyntheticAnswer
    MODEL = "synthetic-local-no-ai"
    Result = Struct.new(:text, :model, keyword_init: true)

    def generate_compiled!(compiled)
      unless (Rails.env.development? || Rails.env.test?) &&
          compiled.is_a?(GenerationInputContract::Compiled) &&
          compiled.mode == "answer" && compiled.provider_called == false &&
          compiled.message_sent == false && compiled.source_ids.any?
        raise Errors::ProviderUnavailable, "Synthetic mode unavailable."
      end

      payload = JSON.parse(compiled.user_content)
      excerpts = payload.fetch("excerpts")
      unless excerpts.is_a?(Array) && excerpts.any? &&
          excerpts.size == compiled.source_ids.size &&
          excerpts.all? { |row| row.is_a?(Hash) && row["text"].is_a?(String) }
        raise Errors::InvalidSelection, "Invalid synthetic input."
      end

      source = excerpts.map { |row| row.fetch("text") }.join(" ")
      path = source.match(/\b(?:POST|GET|PATCH|PUT|DELETE)\s+\/[a-zA-Z0-9_\-\/]+/)
      code = source.match(/\b(?:400|401|403|404|409|422|500|502|503)\b/)
      context = if path && code
        "В выбранной истории встречаются #{path[0]} и статус #{code[0]}. " \
          "Для диагностики стоит запросить текст ошибки, параметры запроса " \
          "и правила валидации."
      else
        "Для продолжения обсуждения стоит уточнить ожидаемый результат, " \
          "подтверждённые исходные данные и критерии приёмки."
      end
      text = "[СИНТЕТИЧЕСКИЙ ТЕСТ — ответ создан без AI и без расходов]\n" \
        "#{context} Бюджет, сроки и обязательства не следует считать согласованными " \
        "без явного подтверждения сторон."

      Result.new(text: text.freeze, model: MODEL).freeze
    rescue JSON::ParserError, KeyError, TypeError
      raise Errors::InvalidSelection, "Invalid synthetic input."
    end
  end
end
