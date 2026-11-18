# frozen_string_literal: true

module AiWorkspace
  # Bounded, opt-in scanner. No Message callback, provider or automatic Send.
  # The operator must separately enable the Rake task in a vetted environment.
  class OutcomeTriggerProducer
    MAX_POLICIES = 50
    Result = Struct.new(:scanned, :enqueued, :skipped, keyword_init: true)

    def initialize(clock: -> { Time.current }, registry: AutomationRunRegistry.new,
      worker: AutomationOutcomeWorker.new, consent: AutomationConsentGate.new)
      @clock, @registry, @worker, @consent = clock, registry, worker, consent
    end

    def scan_once!(limit: MAX_POLICIES)
      raise ArgumentError, "Invalid scan limit" unless limit.is_a?(Integer) &&
        limit.between?(1, MAX_POLICIES)
      stats = { scanned: 0, enqueued: 0, skipped: 0 }
      AiAutomationPolicy.where(summary_mode: %w[after_messages daily])
        .order(:id).limit(limit).each do |policy|
        stats[:scanned] += 1
        begin
          stats[scan_policy!(policy) ? :enqueued : :skipped] += 1
        rescue Errors::Unauthorized, Errors::ConsentRequired, Errors::InvalidSelection,
          AutomationRunRegistry::Unavailable, ActiveRecord::RecordNotFound
          stats[:skipped] += 1
        end
      end
      Result.new(**stats).freeze
    end

    private

    def scan_policy!(policy)
      room, actor = policy.room, policy.user
      return false unless room.is_private?
      room.with_lock do
        policy.reload
        return false unless %w[after_messages daily].include?(policy.summary_mode)
        @consent.check!(room: room, actor: actor, mode: "outcome")
        return false unless AiAutomationPolicy::PREVIEW_KINDS.include?(policy.summary_kind)

        if policy.summary_mode == "after_messages"
          after_threshold!(policy: policy, room: room, actor: actor)
        else
          previous_utc_day!(policy: policy, room: room, actor: actor)
        end
      end
    end

    def after_threshold!(policy:, room:, actor:)
      cursor = AiOutcomeScheduleCursor.find_by(ai_automation_policy: policy)
      unless cursor && cursor.policy_revision == policy.revision
        fresh = cursor || AiOutcomeScheduleCursor.new(ai_automation_policy: policy)
        fresh.update!(policy_revision: policy.revision,
          last_message_id: room.messages.maximum(:id) || 0)
        return false
      end
      participants = room.participants.pluck(:user_id)
      source = room.messages.where(user_id: participants)
        .where("messages.id > ?", cursor.last_message_id)
      return false if source.count < policy.summary_after_messages

      upper = source.maximum(:id)
      run = @registry.capture_outcome!(room: room, actor: actor,
        window_key: "after_messages:#{upper}",
        after_message_id: cursor.last_message_id, through_message_id: upper)
      @worker.enqueue!(run: run)
      cursor.update!(last_message_id: upper)
      true
    end

    def previous_utc_day!(policy:, room:, actor:)
      day = @clock.call.utc.to_date - 1
      start_at = Time.utc(day.year, day.month, day.day)
      finish_at = start_at + 86_400
      return false unless policy.updated_at < finish_at
      participants = room.participants.pluck(:user_id)
      return false unless room.messages.where(user_id: participants,
        created_at: start_at...finish_at).exists?

      run = @registry.capture_outcome!(room: room, actor: actor,
        window_key: "daily:#{day.iso8601}", utc_day: day)
      @worker.enqueue!(run: run)
      true
    end
  end
end
