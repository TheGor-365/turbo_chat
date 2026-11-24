# frozen_string_literal: true

module AiWorkspace
  # Context-to-deliverable tasks are manual, ephemeral and development-only.
  # All current participants must consent; output is not published or saved.
  class ContextTaskGeneration
    Result = Struct.new(:text, :model, :kind, :cost_ticks,
      :source_ids, :omitted, :room_instruction_revision, :evidence_review, :structured_review, keyword_init: true)

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
      source_token: nil, selected_ids: nil, include_room_instructions: nil)
      raise Errors::ProviderUnavailable, "Context tasks unavailable." unless self.class.enabled?
      raise Errors::ConsentRequired, "Confirm this one external request." unless confirmed == "1"
      ConversationTaskV1.fetch!(kind)
      note = ContextReplyPromptV1.validate_hint!(hint)
      include_instruction = RoomInstructionContextV1.opted_in!(include_room_instructions)
      instruction = include_instruction ? RoomInstructionContextV1.load!(
        room: room, actor: actor) : nil
      preflight = @builder.build(room: room, actor: actor, hint: note)
      SourceSelection.apply!(room: room, actor: actor, bundle: preflight,
        hint: note, source_token: source_token, selected_ids: selected_ids,
        room_instruction: instruction)
      reservation = @ledger.reserve!(actor_id: actor.id, request_id: request_id)
      room.reload
      fresh = @builder.build(room: room, actor: actor, hint: note)
      fresh_instruction = include_instruction ? RoomInstructionContextV1.load!(
        room: room, actor: actor) : nil
      bundle = SourceSelection.apply!(room: room, actor: actor, bundle: fresh,
        hint: note, source_token: source_token, selected_ids: selected_ids,
        room_instruction: fresh_instruction)
      policy = ContextAuthorPolicy.new
      grant_revision = policy.fingerprint(room: room, actor: actor)
      SourceSelection.apply!(room: room, actor: actor, bundle: bundle, hint: note)
      options = { kind: kind, hint: note }
      options[:room_instruction] = fresh_instruction if fresh_instruction
      output = @provider_factory.call(ENV.fetch("XAI_API_KEY")).generate_context_task!(
        bundle, **options
      )
      # Account for completed inference even when access changes mid-flight.
      @ledger.settle!(reservation: reservation, cost_ticks: output.cost_in_usd_ticks)
      room.reload
      unless policy.fingerprint(room: room, actor: actor) == grant_revision
        raise Errors::ConsentRequired, "Context permissions changed during generation."
      end
      checked = @builder.build(room: room, actor: actor, hint: note)
      checked_instruction = include_instruction ? RoomInstructionContextV1.load!(
        room: room, actor: actor) : nil
      checked_bundle = SourceSelection.apply!(room: room, actor: actor, bundle: checked,
        hint: note, source_token: source_token, selected_ids: selected_ids,
        room_instruction: checked_instruction)
      unless checked_bundle == bundle &&
          checked_instruction&.revision_number == fresh_instruction&.revision_number &&
          checked_instruction&.sha256 == fresh_instruction&.sha256
        raise Errors::InvalidSelection, "Room context changed during generation."
      end
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
      Result.new(text: output.text, model: output.model, kind: kind,
        cost_ticks: output.cost_in_usd_ticks,
        source_ids: bundle.source_ids, omitted: bundle.omitted,
        room_instruction_revision: fresh_instruction&.revision_number,
        evidence_review: evidence_review, structured_review: structured_review).freeze
    rescue Providers::XaiResponses::ProviderUnavailable
      raise Errors::ProviderUnavailable, "AI generation unavailable."
    end
  end
end
