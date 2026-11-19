# frozen_string_literal: true

module AiWorkspace
  # An explicit paid, user-initiated ANSWER only. Never publishes a Message.
  # Development-only until production privacy, secrets and billing gates pass.
  class AnswerGeneration
    Result = Struct.new(:text, :model, :cost_ticks, :source_ids,
      :goal_revision, keyword_init: true)

    def self.enabled?
      Rails.env.development? &&
        ENV["XAI_ANSWER_GENERATION_ENABLED"] == "1" &&
        ENV["XAI_API_KEY"].to_s.start_with?("xai-") &&
        RoomContextAccess.available? && AiUsageReservation.table_exists?
    rescue ActiveRecord::StatementInvalid, ActiveRecord::NoDatabaseError
      false
    end

    def initialize(planner: GenerationOrchestrator.new,
      ledger: PostgresUsageLedger.new,
      provider_factory: ->(key) { Providers::XaiResponses.new(api_key: key) })
      @planner = planner
      @ledger = ledger
      @provider_factory = provider_factory
    end

    def call(actor:, room:, request_id:, expected_goal_revision:,
      confirmed:, draft_text: "")
      raise Errors::ProviderUnavailable, "AI Answer is disabled." unless self.class.enabled?
      request = GenerationOrchestrator::Request.new(
        mode: "answer", actor: actor, room: room, draft_text: draft_text,
        request_id: request_id, confirmed: confirmed,
        goal_source: "room_instructions",
        expected_goal_revision: expected_goal_revision
      )
      before, = compile!(request)
      reservation = @ledger.reserve!(actor: actor, room: room,
        request_id: request_id, purpose: "contextual_answer")
      provider_started = false
      begin
        # Re-check authorization, source texts, goal, preferences and grants
        # AFTER obtaining the durable transaction-serialized reservation.
        current, = compile!(request)
        raise Errors::InvalidSelection, "Input changed before generation." unless
          current.fingerprint == before.fingerprint

        provider_started = true
        output = @provider_factory.call(ENV.fetch("XAI_API_KEY"))
          .generate_compiled!(current)
        @ledger.settle!(reservation: reservation,
          cost_ticks: output.cost_in_usd_ticks)

        # In-flight consent revocation or membership/goal/source changes
        # invalidate the candidate, even if the provider charged us.
        fresh, plan = compile!(request)
        raise Errors::InvalidSelection, "Room context changed." unless
          fresh.fingerprint == before.fingerprint
        ReplyOutputGuard.validate!(text: output.text,
          bundle: plan.prepared, hint: "")
        unless output.text.is_a?(String) && output.text.present? &&
            output.text.length <= Message::MAX_BODY_LENGTH &&
            output.text.bytesize <= 20_000
          raise Errors::ProviderUnavailable, "Invalid answer length."
        end

        Result.new(text: output.text, model: output.model,
          cost_ticks: output.cost_in_usd_ticks, source_ids: fresh.source_ids,
          goal_revision: fresh.goal_revision).freeze
      rescue Providers::XaiResponses::ProviderUnavailable
        raise Errors::ProviderUnavailable, "AI provider unavailable."
      ensure
        # On an unknown outcome retain the entire reserve; if no dispatch
        # occurred, settle at zero. Never reverse a settled measured charge.
        if reservation && AiUsageReservation.where(id: reservation.id).pick(:state) == "reserved"
          if provider_started
            @ledger.mark_uncertain!(reservation: reservation)
          else
            @ledger.settle!(reservation: reservation, cost_ticks: 0)
          end
        end
      end
    end

    private

    def compile!(request)
      plan = @planner.prepare(request: request)
      [GenerationInputContract.build!(plan: plan, request: request), plan]
    end
  end
end
