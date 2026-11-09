# frozen_string_literal: true

module AiWorkspace
  # H3c: explicit, own-draft-only, development-only paid call gate.
  # This does not permit room history, automatic correction or production use.
  class ManualDraftGeneration
    Result = Struct.new(:text, :model, :cost_ticks, keyword_init: true)

    def self.enabled?
      Rails.env.development? && ENV["XAI_DRAFT_GENERATION_ENABLED"] == "1" &&
        ENV["XAI_API_KEY"].to_s.start_with?("xai-")
    end

    def initialize(ledger: LocalBudgetLedger.new, preflight: OwnDraftPreflight.new,
      provider_factory: ->(key) { Providers::XaiResponses.new(api_key: key) })
      @ledger = ledger
      @preflight = preflight
      @provider_factory = provider_factory
    end

    def call(actor:, room:, draft_text:, preset_id:, request_id:, confirmed:)
      raise Errors::ProviderUnavailable, "AI generation is disabled." unless self.class.enabled?
      raise Errors::ConsentRequired, "Confirm this single external request." unless confirmed == "1"
      prepared = @preflight.prepare(actor: actor, room: room, draft_text: draft_text,
        preset_id: preset_id, approved_preview: true)
      raise Errors::InvalidSelection, "Remove sensitive data from this draft." unless prepared.rows.first.warnings.empty?

      reservation = @ledger.reserve!(actor_id: actor.id, request_id: request_id)
      # Always recheck current membership immediately before dispatch. The
      # single-host local ledger is not sufficient for production revocation
      # semantics and is intentionally not enabled beyond development.
      room.reload
      raise Errors::Unauthorized, "Conversation unavailable." unless room.accessible_to?(actor)
      provider = @provider_factory.call(ENV.fetch("XAI_API_KEY"))
      output = provider.generate!(prepared)
      @ledger.settle!(reservation: reservation, cost_ticks: output.cost_in_usd_ticks)
      Result.new(text: output.text, model: output.model,
        cost_ticks: output.cost_in_usd_ticks).freeze
    rescue Providers::XaiResponses::ProviderUnavailable
      # Unknown billing outcome: hold the reserved $0.10 conservatively.
      raise Errors::ProviderUnavailable, "AI generation unavailable."
    end
  end
end
