# frozen_string_literal: true

module AiWorkspace
  # Code-owned commercial work products, distinct from personal writing styles.
  # This registry supplies metadata, never provider instructions or user prompts.
  class BusinessPresetRegistryV1
    VERSION = 1
    Definition = Struct.new(:key, :version, :task_kind, :audience, :tone,
      :output_format, :required_sections, :review_checks, :max_sources,
      :max_output_tokens, :revision_policy, keyword_init: true) do
      def snapshot
        {
          key: key, version: version, task_kind: task_kind, audience: audience,
          tone: tone, output_format: output_format,
          required_sections: required_sections, review_checks: review_checks,
          max_sources: max_sources, max_output_tokens: max_output_tokens,
          revision_policy: revision_policy
        }.freeze
      end
    end

    # Items in these checklists are questions for a person, not facts extracted
    # from the conversation or statements that anything was agreed.
    CONFIG = {
      "agency/client_brief" => {
        kind: "client_brief", audience: "client", tone: "professional",
        checks: %w[scope acceptance budget deadline]
      },
      "agency/client_proposal" => {
        kind: "client_proposal", audience: "client", tone: "professional",
        checks: %w[scope budget deadline approval]
      },
      "agency/client_summary" => {
        kind: "conversation_summary", audience: "team", tone: "neutral",
        checks: %w[decisions owners approval]
      }
    }.freeze

    PRESETS = CONFIG.to_h do |key, config|
      kind = config.fetch(:kind)
      sections = SemanticDeliverableGateV1::REQUIRED_SECTIONS.fetch(kind)
      max_tokens = ConversationTaskV1.fetch!(kind).fetch(:max_output_tokens)
      preset = Definition.new(
        key: key, version: VERSION, task_kind: kind,
        audience: config.fetch(:audience), tone: config.fetch(:tone),
        output_format: "h4_structured_markdown",
        required_sections: sections.dup.freeze,
        review_checks: config.fetch(:checks).dup.freeze,
        max_sources: ReplyContextBuilder::MAX_MESSAGES,
        max_output_tokens: max_tokens, revision_policy: "explicit_save"
      ).freeze
      [key, preset]
    end.freeze
    BY_KIND = PRESETS.values.to_h { |preset| [preset.task_kind, preset] }.freeze

    def self.fetch!(key:, version: VERSION)
      unless key.instance_of?(String) && version.instance_of?(Integer) &&
          version == VERSION && PRESETS.key?(key)
        raise Errors::InvalidPreset, "Unsupported business preset."
      end
      PRESETS.fetch(key)
    end

    def self.for_task(kind)
      BY_KIND[kind] if kind.instance_of?(String)
    end
  end
end
