# frozen_string_literal: true

module AiWorkspace
  # An explicit paid, user-initiated ANSWER only. Never publishes a Message.
  # Development-only until production privacy, secrets and billing gates pass.
  class AnswerGeneration
    Result = Struct.new(:text, :model, :cost_ticks, :source_ids,
      :goal_revision, :request_id, :fingerprint, :synthetic, keyword_init: true)

    # Two mutually exclusive modes, both forbidden in production.
    # A synthetic demo NEVER contacts xAI or consumes a budget reservation.
    def self.synthetic_enabled?
      Rails.env.development? &&
        ENV["TURBO_CHAT_AI_ANSWER_SYNTHETIC"] == "1" &&
        ENV["XAI_ANSWER_GENERATION_ENABLED"] != "1" &&
        RoomContextAccess.available? && AiUsageReservation.table_exists?
    rescue ActiveRecord::StatementInvalid, ActiveRecord::NoDatabaseError
      false
    end

    def self.live_enabled?
      Rails.env.development? &&
        ENV["XAI_ANSWER_GENERATION_ENABLED"] == "1" &&
        ENV["TURBO_CHAT_AI_ANSWER_SYNTHETIC"] != "1" &&
        ENV["XAI_API_KEY"].to_s.start_with?("xai-") &&
        RoomContextAccess.available? && AiUsageReservation.table_exists?
    rescue ActiveRecord::StatementInvalid, ActiveRecord::NoDatabaseError
      false
    end

    def self.enabled?
      synthetic_enabled? || live_enabled?
    end

    def initialize(planner: GenerationOrchestrator.new(access: RoomContextAccess::Independent.new),
      ledger: PostgresUsageLedger.new,
      provider_factory: ->(key) { Providers::XaiResponses.new(api_key: key) })
      @planner = planner
      @ledger = ledger
      @provider_factory = provider_factory
    end

    def call(actor:, room:, request_id:, expected_goal_revision:,
      confirmed:, draft_text: "", source_token: nil, selected_ids: nil, reply_target_id: nil)
      raise Errors::ProviderUnavailable, "AI Answer is disabled." unless self.class.enabled?
      personal_revision = PersonalEnablement.authorize!(actor: actor).revision
      request = GenerationOrchestrator::Request.new(
        mode: "answer", actor: actor, room: room, draft_text: draft_text,
        request_id: request_id, confirmed: confirmed,
        goal_source: "room_instructions",
        expected_goal_revision: expected_goal_revision,
        source_token: source_token, selected_ids: selected_ids,
        reply_target_id: reply_target_id
      )
      before, = compile!(request)
      PersonalEnablement.authorize!(actor: actor, expected_revision: personal_revision)
      return generate_synthetic!(request: request, before: before,
        personal_revision: personal_revision) if self.class.synthetic_enabled?

      reservation = @ledger.reserve!(actor: actor, room: room,
        request_id: request_id, purpose: "contextual_answer")
      provider_started = false
      begin
        # Re-check authorization, source texts, goal, preferences and grants
        # AFTER obtaining the durable transaction-serialized reservation.
        current, = compile!(request)
        raise Errors::InvalidSelection, "Input changed before generation." unless
          current.fingerprint == before.fingerprint

        PersonalEnablement.authorize!(actor: actor, expected_revision: personal_revision)
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
        validate_output!(text: output.text, plan: plan)
        PersonalEnablement.authorize!(actor: actor, expected_revision: personal_revision)

        Result.new(text: output.text, model: output.model,
          cost_ticks: output.cost_in_usd_ticks, source_ids: fresh.source_ids,
          goal_revision: fresh.goal_revision, request_id: request_id,
          fingerprint: fresh.fingerprint, synthetic: false).freeze
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

    # This path is deliberately independent of xAI credentials and the money
    # ledger. Same code-owned compiled envelope, same consent / ACL / goal
    # checks, same output guard, same Send-time fingerprint validation.
    def generate_synthetic!(request:, before:, personal_revision:)
      current, = compile!(request)
      raise Errors::InvalidSelection, "Input changed before generation." unless
        current.fingerprint == before.fingerprint

      PersonalEnablement.authorize!(actor: request.actor, expected_revision: personal_revision)
      output = SyntheticAnswer.new.generate_compiled!(current)

      fresh, plan = compile!(request)
      raise Errors::InvalidSelection, "Room context changed." unless
        fresh.fingerprint == before.fingerprint
      validate_output!(text: output.text, plan: plan)

      PersonalEnablement.authorize!(actor: request.actor, expected_revision: personal_revision)
      Result.new(text: output.text, model: output.model, cost_ticks: 0,
        source_ids: fresh.source_ids, goal_revision: fresh.goal_revision,
        request_id: request.request_id, fingerprint: fresh.fingerprint,
        synthetic: true).freeze
    end

    def validate_output!(text:, plan:)
      ReplyOutputGuard.validate!(text: text, bundle: plan.prepared, hint: "")
      unless text.is_a?(String) && text.present? &&
          text.length <= Message::MAX_BODY_LENGTH && text.bytesize <= 20_000
        raise Errors::ProviderUnavailable, "Invalid answer length."
      end
    end

    def compile!(request)
      plan = @planner.prepare(request: request)
      [GenerationInputContract.build!(plan: plan, request: request), plan]
    end
  end
end
