# frozen_string_literal: true

module AiWorkspace
  # A deterministic, offline task suggestion made only after the existing
  # membership / all-member-consent / DLP source-preview gate.
  # It never loads history, calls a model, stores data, or spends money.
  class SmartWorkflowV1
    VERSION = 1
    DEFAULT_KIND = "conversation_summary"

    SIGNALS = {
      "client_proposal" => /
        client\s+proposal|commercial\s+offer|коммерческ\p{L}*\s+предложен\p{L}*|
        propuesta\s+comercial|presupuesto\s+comercial|առևտրային\s+առաջարկ
      /ixu,
      "client_brief" => /
        client\s+brief|project\s+requirements|acceptance\s+criteria|
        бриф\s+клиент\p{L}*|техническ\p{L}*\s+задани\p{L}*|
        критерии\s+приёмки|criterios\s+de\s+aceptaci[oó]n|
        requisitos\s+del\s+proyecto|հաճախորդի\s+բրիֆ|տեխնիկական\s+առաջադրանք
      /ixu,
      "action_items" => /
        action\s+items|next\s+steps|to[ -]?do\s+list|
        список\s+задач|следующ\p{L}*\s+шаг\p{L}*|план\s+действий|
        lista\s+de\s+tareas|pr[oó]ximos\s+pasos|
        գործողությունների\s+ցանկ|հաջորդ\s+քայլեր
      /ixu,
      "content_outline" => /
        content\s+(?:plan|outline)|blog\s+(?:post|article)|
        контент[ -]?план|план\s+контента|
        plan\s+de\s+contenido|esquema\s+de\s+contenido|
        բովանդակության\s+պլան|բովանդակության\s+ուրվագիծ
      /ixu
    }.freeze
    # An advisory writing-style preset from the existing immutable registry.
    # Never auto-select a translation target: it requires a human choice.
    STYLE_BY_KIND = {
      "conversation_summary" => "technical_summary",
      "action_items" => "concise",
      "client_brief" => "technical_summary",
      "client_proposal" => "professional_client_reply",
      "content_outline" => "polish_clarity"
    }.freeze
    Result = Struct.new(:version, :kind, :style_id, keyword_init: true)

    def self.suggest(bundle:, hint: nil)
      latest_incoming = bundle.rows.reverse.find { |row| row.speaker != "you" }
      text = [hint.to_s, latest_incoming&.text.to_s].join(" ").slice(0, 1_200)
      kind = SIGNALS.find { |_key, pattern| pattern.match?(text) }&.first ||
        DEFAULT_KIND
      ConversationTaskV1.fetch!(kind)
      style_id = STYLE_BY_KIND.fetch(kind)
      # Fail closed if a future bundled preset revision removes a style.
      PresetRegistry.bundled.fetch(style_id)
      Result.new(version: VERSION, kind: kind, style_id: style_id).freeze
    end
  end
end
