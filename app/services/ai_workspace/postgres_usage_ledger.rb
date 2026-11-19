# frozen_string_literal: true

require "digest"
require "securerandom"

module AiWorkspace
  # S6 first slice: PostgreSQL transaction-scoped advisory lock serializes
  # ALL reservations and settlements across web/worker processes. This is
  # accounting only, NOT provider authorization or a live production gateway.
  #
  # Unknown billing outcomes KEEP the full reservation. Never automatically
  # expire or refund them, including across a period boundary. Manual
  # reconciliation needs a separately audited feature.
  class PostgresUsageLedger
    REQUEST_TICKS = 1_000_000_000 # $0.10 in units of 1e-10 USD
    USER_DAILY_TICKS = 3_000_000_000
    USER_MONTHLY_TICKS = 10_000_000_000
    ROOM_MONTHLY_TICKS = 10_000_000_000
    GLOBAL_MONTHLY_TICKS = 20_000_000_000
    USER_OUTSTANDING_TICKS = 3_000_000_000
    GLOBAL_OUTSTANDING_TICKS = 20_000_000_000
    REQUEST_ID = LocalBudgetLedger::REQUEST_ID
    PG_LOCK_KEY = 7_223_918_271_981 # project-wide constant; never derived from user input

    Reservation = Struct.new(:id, :request_key_hash, :reserved_ticks,
      :state, keyword_init: true)

    def initialize(clock: -> { Time.current.utc })
      @clock = clock
    end

    def reserve!(actor:, room:, request_id:, purpose:)
      validate_request!(actor: actor, room: room, request_id: request_id, purpose: purpose)
      at = @clock.call.utc
      today = at.to_date
      month = today.beginning_of_month
      key = Digest::SHA256.hexdigest("#{actor.id}:#{request_id.downcase}")
      result = nil

      locked_transaction do
        # No request ID may be reused, even after settlement. A collision
        # across room/purpose is never an authorization to repeat a call.
        deny! if AiUsageReservation.exists?(request_key_hash: key)
        deny! unless room.reload.accessible_to?(actor)

        scopes = AiUsageReservation
        monthly = scopes.where(month_utc: month)
        daily_user = scopes.where(user_id: actor.id, day_utc: today)
        monthly_user = monthly.where(user_id: actor.id)
        monthly_room = monthly.where(room_id: room.id)
        outstanding = scopes.where(state: %w[reserved uncertain])
        amounts = [
          [daily_user.sum(:allocated_ticks), USER_DAILY_TICKS],
          [monthly_user.sum(:allocated_ticks), USER_MONTHLY_TICKS],
          [monthly_room.sum(:allocated_ticks), ROOM_MONTHLY_TICKS],
          [monthly.sum(:allocated_ticks), GLOBAL_MONTHLY_TICKS],
          [outstanding.where(user_id: actor.id).sum(:allocated_ticks), USER_OUTSTANDING_TICKS],
          [outstanding.sum(:allocated_ticks), GLOBAL_OUTSTANDING_TICKS]
        ]
        deny! if amounts.any? { |used, ceiling| used + REQUEST_TICKS > ceiling }

        row = AiUsageReservation.create!(user: actor, room: room, purpose: purpose,
          request_key_hash: key, state: "reserved", day_utc: today, month_utc: month,
          reserved_ticks: REQUEST_TICKS, allocated_ticks: REQUEST_TICKS)
        result = Reservation.new(id: row.id, request_key_hash: key,
          reserved_ticks: REQUEST_TICKS, state: "reserved").freeze
      end
      result
    end

    # A provider may charge above the reservation. Preserve the *actual*
    # charge before raising; never silently cap, drop or reverse the record.
    # Duplicate settlement with the SAME cost is safe and read-only.
    def settle!(reservation:, cost_ticks:)
      deny! unless reservation.is_a?(Reservation) &&
        cost_ticks.is_a?(Integer) && cost_ticks.between?(0, 9_000_000_000_000_000)
      overage = false

      locked_transaction do
        row = find_reservation!(reservation)
        if row.state == "settled"
          deny! unless row.actual_ticks == cost_ticks
          overage = cost_ticks > row.reserved_ticks
        elsif %w[reserved uncertain].include?(row.state)
          row.update!(state: "settled", actual_ticks: cost_ticks,
            allocated_ticks: cost_ticks, settled_at: @clock.call.utc)
          overage = cost_ticks > row.reserved_ticks
        else
          deny!
        end
      end
      deny! if overage
      true
    end

    # On timeout, 5xx or unknown provider billing: retain the full charge
    # reservation. Repeating the same request ID still fails.
    def mark_uncertain!(reservation:)
      deny! unless reservation.is_a?(Reservation)

      locked_transaction do
        row = find_reservation!(reservation)
        return true if row.state == "uncertain"
        deny! unless row.state == "reserved"

        row.update!(state: "uncertain", uncertain_at: @clock.call.utc)
      end
      true
    end

    private

    def locked_transaction
      ActiveRecord::Base.transaction(requires_new: true) do
        # PostgreSQL advisory xact lock: auto-release on commit/rollback.
        # Every mutation in this ledger must take this same lock.
        ActiveRecord::Base.connection.select_value(
          "SELECT pg_advisory_xact_lock(#{PG_LOCK_KEY})"
        )
        yield
      end
    rescue ActiveRecord::ConnectionNotEstablished, ActiveRecord::StatementInvalid,
      ActiveRecord::RecordInvalid, ActiveRecord::RecordNotUnique
      raise Errors::BudgetExceeded, "Usage budget unavailable"
    end

    def validate_request!(actor:, room:, request_id:, purpose:)
      deny! unless actor&.persisted? && room&.persisted? &&
        room.accessible_to?(actor) && request_id.is_a?(String) &&
        request_id.match?(REQUEST_ID) && AiUsageReservation::PURPOSES.include?(purpose)
    end

    def find_reservation!(reservation)
      row = AiUsageReservation.lock.find_by(id: reservation.id,
        request_key_hash: reservation.request_key_hash)
      deny! unless row && row.reserved_ticks == reservation.reserved_ticks
      row
    end

    def deny!
      raise Errors::BudgetExceeded, "Usage budget unavailable or exhausted"
    end
  end
end
