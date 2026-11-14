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
    Result = Struct.new(:version, :kind, keyword_init: true)

    def self.suggest(bundle:, hint: nil)
      latest_incoming = bundle.rows.reverse.find { |row| row.speaker != "you" }
      text = [hint.to_s, latest_incoming&.text.to_s].join(" ").slice(0, 1_200)
      kind = SIGNALS.find { |_key, pattern| pattern.match?(text) }&.first ||
        DEFAULT_KIND
      ConversationTaskV1.fetch!(kind)
      Result.new(version: VERSION, kind: kind).freeze
    end
  end
end
