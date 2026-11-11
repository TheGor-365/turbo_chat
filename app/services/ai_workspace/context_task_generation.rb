# frozen_string_literal: true

module AiWorkspace
  # Context-to-deliverable tasks are manual, ephemeral and development-only.
  # All current participants must consent; output is not published or saved.
  class ContextTaskGeneration
    Result = Struct.new(:text, :model, :kind, :cost_ticks,
      :source_ids, :omitted, :evidence_review, :structured_review, keyword_init: true)

    def self.enabled?
      ContextReplyGeneration.enabled? && ENV["XAI_CONTEXT_TASKS_ENABLED"] == "1"
    end

    def initialize(builder: ReplyContextBuilder.new, ledger: LocalBudgetLedger.new,
      provider_factory: ->(key) { Providers::XaiResponses.new(api_key: key) })
      @builder = builder
      @ledger = ledger
      @provider_factory = provider_factory
    end

    def call(actor:, room:, kind:, request_id:, confirmed:, hint: nil,
      source_token: nil, selected_ids: nil)
      raise Errors::ProviderUnavailable, "Context tasks unavailable." unless self.class.enabled?
      raise Errors::ConsentRequired, "Confirm this one external request." unless confirmed == "1"
      ConversationTaskV1.fetch!(kind)
      note = ContextReplyPromptV1.validate_hint!(hint)
      preflight = @builder.build(room: room, actor: actor, hint: note)
      SourceSelection.apply!(room: room, actor: actor, bundle: preflight,
        hint: note, source_token: source_token, selected_ids: selected_ids)
      reservation = @ledger.reserve!(actor_id: actor.id, request_id: request_id)
      room.reload
      fresh = @builder.build(room: room, actor: actor, hint: note)
      bundle = SourceSelection.apply!(room: room, actor: actor, bundle: fresh,
        hint: note, source_token: source_token, selected_ids: selected_ids)
      output = @provider_factory.call(ENV.fetch("XAI_API_KEY")).generate_context_task!(
        bundle, kind: kind, hint: note
      )
      ReplyOutputGuard.validate!(text: output.text, bundle: bundle, hint: note)
      evidence_review = EvidenceReviewV1.inspect!(text: output.text, bundle: bundle)
      # This is advisory. A model may produce malformed Markdown even after
      # a paid request: preserve the billable output and settle the ledger,
      # never silently mark a model claim approved or drop payment accounting.
      structured_review = nil
      if SemanticDeliverableGateV1::REQUIRED_SECTIONS.key?(kind)
        begin
          checked = SemanticDeliverableGateV1.inspect!(
            text: output.text, kind: kind, bundle: bundle
          )
          structured_review = {
            version: 1, complete: checked.complete,
            warnings: checked.warnings, review_state: checked.document.review_state
          }.freeze
        rescue Errors::InvalidSelection
          structured_review = {
            version: 1, complete: false,
            warnings: ["Output is not a valid structured document; manual review required."].freeze,
            review_state: "unavailable"
          }.freeze
        end
      end
      @ledger.settle!(reservation: reservation, cost_ticks: output.cost_in_usd_ticks)
      Result.new(text: output.text, model: output.model, kind: kind,
        cost_ticks: output.cost_in_usd_ticks,
        source_ids: bundle.source_ids, omitted: bundle.omitted,
        evidence_review: evidence_review, structured_review: structured_review).freeze
    rescue Providers::XaiResponses::ProviderUnavailable
      raise Errors::ProviderUnavailable, "AI generation unavailable."
    end
  end
end
