# frozen_string_literal: true

require "digest"
require "json"

module AiWorkspace
  # S6 mock-stage integration of S3 preflight and the EXISTING PG ledger.
  # Deliberately TEST-ONLY. This cannot dispatch any production paid request;
  # a separately approved provider adapter + release gate is still required.
  # It never persists a Message or uses any automated Send capability.
  class MeteredGenerationGateway
    Result = Struct.new(:text, :mode, :model, :cost_ticks, :source_ids,
      :goal_revision, :simulated, :message_sent, keyword_init: true)

    def initialize(planner: GenerationOrchestrator.new,
      ledger: PostgresUsageLedger.new, transport: Gateway)
      @planner, @ledger, @transport = planner, ledger, transport
    end

    def call(request:)
      unless Rails.env.test? && @transport != Gateway && @transport.respond_to?(:generate!)
        raise Errors::ProviderUnavailable, "Live AI transport is not authorized."
      end

      first = @planner.prepare(request: request)
      raise Errors::ProviderUnavailable, "Automated Send is disabled." if first.mode == "auto_reply"
      purpose = first.mode == "beautify" ? "beautify" : "contextual_answer"
      original_fingerprint = fingerprint(first)
      reservation = @ledger.reserve!(actor: request.actor, room: request.room,
        request_id: first.request_id, purpose: purpose)

      begin
        current = @planner.prepare(request: request)
        raise Errors::InvalidSelection, "Generation context changed." unless
          fingerprint(current) == original_fingerprint
        output = @transport.generate!(plan: current)
        validate_mock_charge!(output)
      rescue Errors::InvalidSelection, Errors::ConsentRequired, Errors::Unauthorized
        @ledger.mark_uncertain!(reservation: reservation)
        raise
      rescue StandardError
        # The mock provider might have returned or failed after a side effect.
        # Preserve the reservation until a separate reconciliation, never refund.
        @ledger.mark_uncertain!(reservation: reservation)
        raise Errors::ProviderUnavailable, "Generation transport unavailable."
      end

      # The provider's validated cost envelope is accounted for BEFORE
      # output/DLP review. A rejected or stale draft can still have a known
      # billable cost. An overage stays recorded and prevents returning text.
      @ledger.settle!(reservation: reservation, cost_ticks: output.cost_in_usd_ticks)
      fresh = @planner.prepare(request: request)
      raise Errors::InvalidSelection, "Generation context changed." unless
        fingerprint(fresh) == original_fingerprint
      validate_mock_output!(output, fresh, request)

      Result.new(text: output.text, mode: first.mode, model: output.model,
        cost_ticks: output.cost_in_usd_ticks, source_ids: first.source_ids,
        goal_revision: first.goal_snapshot&.fetch(:revision),
        simulated: true, message_sent: false).freeze
    end

    private

    def fingerprint(plan)
      rows = plan.prepared.rows.map(&:to_h)
      Digest::SHA256.hexdigest(JSON.generate([
        plan.mode, plan.request_id, plan.actor_id, plan.room_id,
        plan.source, plan.source_ids, plan.goal_snapshot,
        plan.preferences, rows,
        plan.prepared.respond_to?(:preset_snapshot) ? plan.prepared.preset_snapshot : nil
      ]))
    end

    # A missing/untrustworthy usage envelope retains the uncertain reserve.
    # Once this envelope is valid, settle before rejecting unsafe content.
    def validate_mock_charge!(output)
      unless output.is_a?(Providers::XaiResponses::Result) &&
          output.model == "mock-only" &&
          output.cost_in_usd_ticks.is_a?(Integer) &&
          output.cost_in_usd_ticks.between?(0, 9_000_000_000_000_000)
        raise Errors::ProviderUnavailable, "Invalid mock generation charge."
      end
    end

    def validate_mock_output!(output, plan, request)
      unless output.text.is_a?(String) &&
          output.text.strip.present? && output.text.bytesize <= 8_000
        raise Errors::ProviderUnavailable, "Invalid mock generation result."
      end
      checked = Preprocessors::Text.call(output.text)
      raise Errors::ProviderUnavailable, "Unsafe generation result." unless checked.warnings.empty?
      if plan.mode == "answer"
        ReplyOutputGuard.validate!(text: checked.text,
          bundle: plan.prepared, hint: request.hint)
      end
      true
    end
  end
end
