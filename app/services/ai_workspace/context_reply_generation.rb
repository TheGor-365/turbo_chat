# frozen_string_literal: true

module AiWorkspace
  # H3g: development-only contextual replies. Opt-in is a persistent,
  # revocable room/member grant; EACH paid call still needs consent == "1".
  # Results are ephemeral and NEVER create chat messages.
  class ContextReplyGeneration
    Result = Struct.new(:text, :model, :cost_ticks, :source_ids, :omitted, :room_instruction_revision, :evidence_review, keyword_init: true)

    def self.enabled?
      ManualDraftGeneration.enabled? && ENV["XAI_CONTEXT_REPLIES_ENABLED"] == "1" &&
        RoomContextAccess.available?
    end

    def initialize(builder: ReplyContextBuilder.new, ledger: LocalBudgetLedger.new,
      provider_factory: ->(key) { Providers::XaiResponses.new(api_key: key) })
      @builder = builder
      @ledger = ledger
      @provider_factory = provider_factory
    end

    def call(actor:, room:, request_id:, confirmed:, hint: nil,
      source_token: nil, selected_ids: nil, include_room_instructions: nil)
      raise Errors::ProviderUnavailable, "Contextual AI is disabled." unless self.class.enabled?
      raise Errors::ConsentRequired, "Confirm this one external request." unless confirmed == "1"
      note = ContextReplyPromptV1.validate_hint!(hint)
      include_instruction = RoomInstructionContextV1.opted_in!(include_room_instructions)
      instruction = include_instruction ? RoomInstructionContextV1.load!(
        room: room, actor: actor) : nil
      preflight = @builder.build(room: room, actor: actor, hint: note)
      SourceSelection.apply!(room: room, actor: actor, bundle: preflight,
        hint: note, source_token: source_token, selected_ids: selected_ids,
        room_instruction: instruction) # no charge if stale
      reservation = @ledger.reserve!(actor_id: actor.id, request_id: request_id)

      # Re-read membership and grants immediately before external dispatch.
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
      options = { hint: note }
      options[:room_instruction] = fresh_instruction if fresh_instruction
      output = @provider_factory.call(ENV.fetch("XAI_API_KEY")).generate_reply!(bundle, **options)
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

      Result.new(text: output.text, model: output.model,
        cost_ticks: output.cost_in_usd_ticks,
        source_ids: bundle.source_ids, omitted: bundle.omitted,
        room_instruction_revision: fresh_instruction&.revision_number,
        evidence_review: evidence_review).freeze
    rescue Providers::XaiResponses::ProviderUnavailable
      # Provider billing may have happened, so the $0.10 reservation remains.
      raise Errors::ProviderUnavailable, "AI generation unavailable."
    end
  end
end
