# frozen_string_literal: true

require "json"
require "fileutils"
require "digest"

module AiWorkspace
  # Conservative, persistent, single-host DEVELOPMENT budget ledger.
  # File#flock works across local Rails processes sharing this filesystem.
  # Never use this backend for a multi-host deployment.
  class LocalBudgetLedger
    RESERVATION_TICKS = 1_000_000_000 # $0.10, includes possible xAI safety fee
    DAILY_USER_TICKS = 3_000_000_000 # $0.30
    MONTHLY_USER_TICKS = 10_000_000_000 # $1.00
    MONTHLY_GLOBAL_TICKS = 20_000_000_000 # $2.00
    REQUEST_ID = /\A[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}\z/i

    def initialize(path: Rails.root.join("storage", "ai_h3_local_budget.json"), clock: -> { Time.now.utc })
      @path = Pathname(path)
      @clock = clock
    end

    def reserve!(actor_id:, request_id:)
      raise Errors::BudgetExceeded, "Budget unavailable." unless Rails.env.development? || Rails.env.test?
      unless actor_id.is_a?(Integer) && actor_id.positive? && request_id.is_a?(String) &&
          request_id.match?(REQUEST_ID)
        raise Errors::BudgetExceeded, "Budget unavailable."
      end
      at = @clock.call.utc
      day = at.strftime("%Y-%m-%d")
      month = at.strftime("%Y-%m")
      digest = Digest::SHA256.hexdigest("#{actor_id}:#{request_id}")
      with_file do |data|
        entries = data.fetch("entries")
        # Old entries no longer affect daily or monthly budgets.
        entries.delete_if { |_, v| v["month"] < (at.to_date << 1).strftime("%Y-%m") }
        raise Errors::BudgetExceeded, "Duplicate AI request." if entries.key?(digest)
        today = entries.values.select { |v| v["actor_id"] == actor_id && v["day"] == day }
        this_month = entries.values.select { |v| v["actor_id"] == actor_id && v["month"] == month }
        global_month = entries.values.select { |v| v["month"] == month }
        [[today, DAILY_USER_TICKS], [this_month, MONTHLY_USER_TICKS],
          [global_month, MONTHLY_GLOBAL_TICKS]].each do |records, cap|
          if records.sum { |v| v["charged_ticks"] } + RESERVATION_TICKS > cap
            raise Errors::BudgetExceeded, "AI budget limit reached."
          end
        end
        entries[digest] = {
          "actor_id" => actor_id, "day" => day, "month" => month,
          "charged_ticks" => RESERVATION_TICKS, "state" => "reserved"
        }
        digest
      end
    end

    def settle!(reservation:, cost_ticks:)
      unless reservation.is_a?(String) && reservation.match?(/\A[0-9a-f]{64}\z/) &&
          cost_ticks.is_a?(Integer) && cost_ticks >= 0
        raise Errors::BudgetExceeded, "Budget unavailable."
      end
      with_file do |data|
        row = data.fetch("entries")[reservation]
        raise Errors::BudgetExceeded, "Budget unavailable." unless row && row["state"] == "reserved"
        # xAI can charge even on rejected requests; unknown outcomes keep the
        # entire reservation. Record measured overage instead of hiding it.
        row["charged_ticks"] = cost_ticks
        row["state"] = "settled"
        raise Errors::BudgetExceeded, "Per-request cost exceeded." if cost_ticks > RESERVATION_TICKS
        true
      end
    end

    private

    def with_file
      FileUtils.mkdir_p(@path.dirname, mode: 0o700)
      File.open(@path, File::RDWR | File::CREAT, 0o600) do |file|
        file.flock(File::LOCK_EX)
        raw = file.read
        data = raw.empty? ? { "entries" => {} } : JSON.parse(raw)
        raise Errors::BudgetExceeded, "Budget unavailable." unless data.is_a?(Hash) &&
          data["entries"].is_a?(Hash)
        result = yield data
        file.rewind
        file.write(JSON.generate(data))
        file.truncate(file.pos)
        file.flush
        file.fsync
        result
      ensure
        file.flock(File::LOCK_UN) if file
      end
    rescue IOError, SystemCallError, JSON::ParserError, TypeError, KeyError
      raise Errors::BudgetExceeded, "Budget unavailable."
    end
  end
end
