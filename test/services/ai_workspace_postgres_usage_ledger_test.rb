require "test_helper"
require "securerandom"

class AiWorkspacePostgresUsageLedgerTest < ActiveSupport::TestCase
  def setup
    @alice, @bob = users(:one), users(:two)
    @room = Room.create_private_room([@alice, @bob],
      "private_#{[@alice.id, @bob.id].sort.join('_')}")
    @now = Time.utc(2026, 11, 18, 13, 0)
    @ledger = AiWorkspace::PostgresUsageLedger.new(clock: -> { @now })
  end

  def reserve(actor: @alice, room: @room, id: SecureRandom.uuid, purpose: "beautify")
    @ledger.reserve!(actor: actor, room: room, request_id: id, purpose: purpose)
  end

  test "database reservation and UUID uniqueness reject duplicate spending" do
    request_id = SecureRandom.uuid
    first = reserve(id: request_id)
    assert_equal "reserved", AiUsageReservation.find(first.id).state
    assert_equal AiWorkspace::PostgresUsageLedger::REQUEST_TICKS,
      AiUsageReservation.find(first.id).allocated_ticks
    assert_equal 64, first.request_key_hash.length
    assert_raises(AiWorkspace::Errors::BudgetExceeded) { reserve(id: request_id) }
    assert_equal 1, AiUsageReservation.count
    assert_equal 0, @room.messages.count
  end

  test "atomic daily cap rejects fourth reservation and limits persist across instances" do
    3.times { reserve }
    alternate = AiWorkspace::PostgresUsageLedger.new(clock: -> { @now })
    assert_raises(AiWorkspace::Errors::BudgetExceeded) do
      alternate.reserve!(actor: @alice, room: @room, request_id: SecureRandom.uuid,
        purpose: "contextual_answer")
    end
    assert_equal 3, AiUsageReservation.count
    assert_equal 0, @room.messages.count
  end

  test "settlement records actual cost, double settlement is idempotent, conflict denied" do
    row = reserve
    assert @ledger.settle!(reservation: row, cost_ticks: 200_000_000)
    assert @ledger.settle!(reservation: row, cost_ticks: 200_000_000)
    assert_equal "settled", AiUsageReservation.find(row.id).state
    assert_equal 200_000_000, AiUsageReservation.find(row.id).allocated_ticks
    assert_raises(AiWorkspace::Errors::BudgetExceeded) do
      @ledger.settle!(reservation: row, cost_ticks: 300_000_000)
    end
    assert_equal 1, AiUsageReservation.count
    2.times { reserve }
    assert_raises(AiWorkspace::Errors::BudgetExceeded) { reserve }
  end

  test "overage is written before denial and counted toward future budgets" do
    row = reserve
    assert_raises(AiWorkspace::Errors::BudgetExceeded) do
      @ledger.settle!(reservation: row, cost_ticks: 1_500_000_000)
    end
    persisted = AiUsageReservation.find(row.id)
    assert_equal "settled", persisted.state
    assert_equal 1_500_000_000, persisted.actual_ticks
    reserve
    assert_raises(AiWorkspace::Errors::BudgetExceeded) { reserve }
  end

  test "uncertain billing holds funds across times and blocks replay" do
    id = SecureRandom.uuid
    entry = reserve(id: id)
    assert @ledger.mark_uncertain!(reservation: entry)
    assert @ledger.mark_uncertain!(reservation: entry)
    assert_equal "uncertain", AiUsageReservation.find(entry.id).state
    assert_nil AiUsageReservation.find(entry.id).actual_ticks
    @now = Time.utc(2026, 12, 1)
    assert_raises(AiWorkspace::Errors::BudgetExceeded) { reserve(id: id) }
    assert @ledger.settle!(reservation: entry, cost_ticks: 400_000_000)
    assert_raises(AiWorkspace::Errors::BudgetExceeded) do
      @ledger.mark_uncertain!(reservation: entry)
    end
  end

  test "invalid IDs, foreign room or purpose and forged reservation are rejected" do
    outsider = User.create!(email: "usage-outsider@example.test",
      password: "test-password-123")
    assert_raises(AiWorkspace::Errors::BudgetExceeded) { reserve(actor: outsider) }
    assert_raises(AiWorkspace::Errors::BudgetExceeded) { reserve(id: "invalid") }
    assert_raises(AiWorkspace::Errors::BudgetExceeded) { reserve(purpose: "send_without_consent") }
    entry = reserve
    forged = entry.dup
    forged.request_key_hash = "0" * 64
    assert_raises(AiWorkspace::Errors::BudgetExceeded) do
      @ledger.settle!(reservation: forged, cost_ticks: 1)
    end
    assert_equal "reserved", AiUsageReservation.find(entry.id).state
  end

  test "global and room limits do not reset on each user" do
    # The budget is applied to every user in the same room even if each user
    # is individually below their own daily cap.
    3.times { reserve }
    3.times { reserve(actor: @bob) }
    assert_equal 6, AiUsageReservation.count
    assert_raises(AiWorkspace::Errors::BudgetExceeded) { reserve }
  end

  test "accounting creates no messages, deliverables, jobs or provider calls" do
    entry = reserve(purpose: "reply_unattended")
    assert_equal "reserved", AiUsageReservation.find(entry.id).state
    assert_equal 0, @room.messages.count
    assert_equal 0, AiDeliverable.count
    assert_equal false, AiWorkspace::Gateway.configured?
    assert_raises(AiWorkspace::Gateway::ProviderUnavailable) do
      AiWorkspace::Gateway.generate!
    end
  end
end
