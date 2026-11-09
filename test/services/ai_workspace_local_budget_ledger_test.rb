require "test_helper"
require "tmpdir"
require "securerandom"

class AiLocalBudgetLedgerTest < ActiveSupport::TestCase
  def with_budget
    Dir.mktmpdir("h3c_budget_test") do |directory|
      at = Time.utc(2026, 11, 10, 4, 0, 0)
      ledger = AiWorkspace::LocalBudgetLedger.new(
        path: File.join(directory, "budget.json"), clock: -> { at })
      yield ledger, directory
    end
  end

  test "reserves atomically and denies duplicate and fourth request for same user on same day" do
    with_budget do |ledger, directory|
      id = SecureRandom.uuid
      first = ledger.reserve!(actor_id: 1, request_id: id)
      assert_equal 64, first.length
      assert_raises(AiWorkspace::Errors::BudgetExceeded) do
        ledger.reserve!(actor_id: 1, request_id: id)
      end
      2.times { ledger.reserve!(actor_id: 1, request_id: SecureRandom.uuid) }
      assert_raises(AiWorkspace::Errors::BudgetExceeded) do
        ledger.reserve!(actor_id: 1, request_id: SecureRandom.uuid)
      end
      data = JSON.parse(File.read(File.join(directory, "budget.json")))
      assert_equal 3, data.fetch("entries").size
      assert_equal 1_000_000_000, data.fetch("entries").fetch(first).fetch("charged_ticks")
    end
  end

  test "successful metering settles reserve and permits additional bounded calls" do
    with_budget do |ledger, _|
      first = ledger.reserve!(actor_id: 7, request_id: SecureRandom.uuid)
      assert_equal true, ledger.settle!(reservation: first, cost_ticks: 5_000_000)
      3.times { ledger.reserve!(actor_id: 7, request_id: SecureRandom.uuid) }
      assert_raises(AiWorkspace::Errors::BudgetExceeded) do
        ledger.reserve!(actor_id: 7, request_id: SecureRandom.uuid)
      end
      assert_raises(AiWorkspace::Errors::BudgetExceeded) do
        ledger.settle!(reservation: first, cost_ticks: 1)
      end
    end
  end

  test "parallel calls and different actors still share the same persisted ledger" do
    with_budget do |ledger, _|
      results = 12.times.map do
        Thread.new do
          begin
            ledger.reserve!(actor_id: 11, request_id: SecureRandom.uuid)
            true
          rescue AiWorkspace::Errors::BudgetExceeded
            false
          end
        end
      end.map(&:value)
      assert_equal 3, results.count(true)
      assert_equal 9, results.count(false)
      # A different user may use remaining globally available monthly budget.
      assert ledger.reserve!(actor_id: 12, request_id: SecureRandom.uuid)
    end
  end

  test "unknown or over-limit charges fail closed and never refund reservations" do
    with_budget do |ledger, directory|
      first = ledger.reserve!(actor_id: 1, request_id: SecureRandom.uuid)
      assert_raises(AiWorkspace::Errors::BudgetExceeded) do
        ledger.settle!(reservation: first, cost_ticks: 1_500_000_000)
      end
      entry = JSON.parse(File.read(File.join(directory, "budget.json")))
        .fetch("entries").fetch(first)
      assert_equal "settled", entry.fetch("state")
      assert_equal 1_500_000_000, entry.fetch("charged_ticks")
      assert_raises(AiWorkspace::Errors::BudgetExceeded) do
        ledger.reserve!(actor_id: 1, request_id: "bogus")
      end
    end
  end

  test "malformed budget ledger is not reset and cannot authorize billable calls" do
    with_budget do |ledger, directory|
      file = File.join(directory, "budget.json")
      File.write(file, '{"incomplete":')
      assert_raises(AiWorkspace::Errors::BudgetExceeded) do
        ledger.reserve!(actor_id: 1, request_id: SecureRandom.uuid)
      end
      assert_equal '{"incomplete":', File.read(file)
    end
  end
end
