require "test_helper"
require "securerandom"

class AiWorkspaceMeteredGenerationGatewayTest < ActiveSupport::TestCase
  class MockTransport
    attr_reader :calls

    def initialize(&block)
      @calls = 0
      @block = block
    end

    def generate!(plan:)
      @calls += 1
      @block&.call(plan)
      AiWorkspace::Providers::XaiResponses::Result.new(
        text: "Could you clarify the expected Rails form behavior?",
        model: "mock-only", input_tokens: 10, output_tokens: 15,
        cost_in_usd_ticks: 250_000_000)
    end
  end

  def setup
    @alice, @bob = users(:one), users(:two)
    @room = Room.create_private_room([@alice, @bob],
      "private_#{[@alice.id, @bob.id].sort.join('_')}")
    @incoming = @room.messages.create!(user: @bob,
      body: "Can we clarify the required Rails form behavior?")
  end

  def request(mode: "beautify", draft: "Please clarify the Rails form requirements.", **extra)
    AiWorkspace::GenerationOrchestrator::Request.new(
      actor: @alice, room: @room, mode: mode,
      draft_text: draft, request_id: SecureRandom.uuid,
      confirmed: "1", preset_id: (mode == "beautify" ? "polish_clarity" : nil), **extra)
  end

  def grant_answer_context
    [@alice, @bob].each do |user|
      AiRoomContextConsent.find_or_initialize_by(room: @room, user: user).grant!
    end
    AiConversationGoal.create!(user: @alice, room: @room,
      purpose: "Clarify acceptance criteria", revision: 1, active: true)
  end

  test "default gateway cannot use the production transport or reserve money" do
    assert_raises(AiWorkspace::Errors::ProviderUnavailable) do
      AiWorkspace::MeteredGenerationGateway.new.call(request: request)
    end
    assert_equal 0, AiUsageReservation.count
  end

  test "mock output is charged exactly once in PostgreSQL but never creates chat messages" do
    mock = MockTransport.new
    gateway = AiWorkspace::MeteredGenerationGateway.new(transport: mock)
    original = Message.count
    req = request
    output = gateway.call(request: req)
    assert_equal "mock-only", output.model
    assert_equal true, output.simulated
    assert_equal false, output.message_sent
    assert_equal 250_000_000, output.cost_ticks
    assert_equal 1, mock.calls
    assert_equal original, Message.count
    reservation = AiUsageReservation.sole
    assert_equal "settled", reservation.state
    assert_equal 250_000_000, reservation.actual_ticks
    assert_equal 250_000_000, reservation.allocated_ticks
    assert_raises(AiWorkspace::Errors::BudgetExceeded) { gateway.call(request: req) }
    assert_equal 1, mock.calls
  end

  test "unknown mock transport outcome is held as uncertain, with no retry" do
    mock = MockTransport.new { raise IOError, "mock unavailable" }
    gateway = AiWorkspace::MeteredGenerationGateway.new(transport: mock)
    req = request
    assert_raises(AiWorkspace::Errors::ProviderUnavailable) do
      gateway.call(request: req)
    end
    assert_equal "uncertain", AiUsageReservation.sole.state
    assert_nil AiUsageReservation.sole.actual_ticks
    assert_raises(AiWorkspace::Errors::BudgetExceeded) { gateway.call(request: req) }
    assert_equal 1, mock.calls
    assert_equal 1, @room.messages.count
  end

  test "changed goal after mock generation rejects candidate but retains measured cost" do
    grant_answer_context
    mock = MockTransport.new do |_plan|
      goal = AiConversationGoal.find_by!(user: @alice, room: @room)
      goal.update!(purpose: "Revised goal", revision: 2)
    end
    gateway = AiWorkspace::MeteredGenerationGateway.new(transport: mock)
    assert_raises(AiWorkspace::Errors::InvalidSelection) do
      gateway.call(request: request(mode: "answer", draft: "",
        expected_goal_revision: 1))
    end
    assert_equal 1, mock.calls
    assert_equal "settled", AiUsageReservation.sole.state
    assert_equal 250_000_000, AiUsageReservation.sole.actual_ticks
    assert_equal 1, @room.messages.count
  end
end
