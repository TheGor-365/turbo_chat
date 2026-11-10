# frozen_string_literal: true

module AiWorkspace
  # H3g: development-only contextual replies. Opt-in is a persistent,
  # revocable room/member grant; EACH paid call still needs consent == "1".
  # Results are ephemeral and NEVER create chat messages.
  class ContextReplyGeneration
    Result = Struct.new(:text, :model, :cost_ticks, :source_ids, :omitted, keyword_init: true)

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

    def call(actor:, room:, request_id:, confirmed:, hint: nil)
      raise Errors::ProviderUnavailable, "Contextual AI is disabled." unless self.class.enabled?
      raise Errors::ConsentRequired, "Confirm this one external request." unless confirmed == "1"
      note = ContextReplyPromptV1.validate_hint!(hint)
      @builder.build(room: room, actor: actor, hint: note) # fail before spending a reservation
      reservation = @ledger.reserve!(actor_id: actor.id, request_id: request_id)

      # Re-read membership and grants immediately before external dispatch.
      room.reload
      bundle = @builder.build(room: room, actor: actor, hint: note)
      output = @provider_factory.call(ENV.fetch("XAI_API_KEY")).generate_reply!(bundle, hint: note)
      ReplyOutputGuard.validate!(text: output.text, bundle: bundle, hint: note)
      @ledger.settle!(reservation: reservation, cost_ticks: output.cost_in_usd_ticks)

      Result.new(text: output.text, model: output.model,
        cost_ticks: output.cost_in_usd_ticks,
        source_ids: bundle.source_ids, omitted: bundle.omitted).freeze
    rescue Providers::XaiResponses::ProviderUnavailable
      # Provider billing may have happened, so the $0.10 reservation remains.
      raise Errors::ProviderUnavailable, "AI generation unavailable."
    end
  end
end
