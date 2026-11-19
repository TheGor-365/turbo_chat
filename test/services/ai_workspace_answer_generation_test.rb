require "test_helper"
require "securerandom"

class AiWorkspaceAnswerGenerationTest < ActiveSupport::TestCase
  def setup
    @alice, @bob = users(:one), users(:two)
    @room = Room.create_private_room([@alice, @bob],
      "private_#{[@alice.id, @bob.id].sort.join('_')}")
    @incoming = @room.messages.create!(user: @bob,
      body: "POST /orders returns 422. Can you check Rails validation?")
    RoomAiInstructionRevision.create!(room: @room, editor: @alice,
      revision_number: 1, content: "Ask for evidence, never invent budget or deadlines")
    @request_id = SecureRandom.uuid
    @output = AiWorkspace::Providers::XaiResponses::Result.new(
      text: "Please share the Rails validation error for POST /orders (422).",
      model: AiWorkspace::Providers::XaiResponses::MODEL,
      cost_in_usd_ticks: 20_000_000)
    @received = []
    fake = Object.new
    captured = @received
    result = @output
    fake.define_singleton_method(:generate_compiled!) do |compiled|
      captured << compiled
      result
    end
    @factory = ->(_key) { fake }
  end

  def grants!
    [@alice, @bob].each do |person|
      AiRoomContextConsent.find_or_initialize_by(room: @room, user: person).grant!
    end
  end

  def run_answer(id: @request_id, factory: @factory, revision: 1)
    # Synthetic, non-routable fixture: the injected provider never uses HTTP.
    original_key = ENV["XAI_API_KEY"]
    ENV["XAI_API_KEY"] = "xai-synthetic-no-network-fixture"
    service = AiWorkspace::AnswerGeneration.new(provider_factory: factory)
    AiWorkspace::AnswerGeneration.stub(:enabled?, true) do
      service.call(actor: @alice, room: @room, request_id: id,
        expected_goal_revision: revision, confirmed: "1", draft_text: "")
    end
  ensure
    original_key ? ENV["XAI_API_KEY"] = original_key : ENV.delete("XAI_API_KEY")
  end

  test "real S3 compiled request is charged once, retains source and never sends" do
    grants!
    before = @room.messages.count
    result = run_answer
    assert_equal @output.text, result.text
    assert_equal [@incoming.id], result.source_ids
    assert_equal 1, result.goal_revision
    assert_equal 1, @received.size
    assert_equal "answer", @received.sole.mode
    assert_includes @received.sole.user_content, "POST /orders returns 422"
    assert_includes @received.sole.user_content, "Ask for evidence"
    row = AiUsageReservation.sole
    assert_equal "contextual_answer", row.purpose
    assert_equal "settled", row.state
    assert_equal 20_000_000, row.actual_ticks
    assert_equal before, @room.messages.count
    assert_raises(AiWorkspace::Errors::BudgetExceeded) { run_answer }
    assert_equal 1, @received.size
  end

  test "no unanimous grant or stale goal prevents reservation and provider dispatch" do
    assert_raises(AiWorkspace::Errors::ConsentRequired) { run_answer }
    grants!
    assert_raises(AiWorkspace::Errors::InvalidSelection) { run_answer(revision: 2) }
    assert_equal 0, AiUsageReservation.count
    assert_equal [], @received
  end

  test "revocation during provider call discards result but charges measured amount" do
    grants!
    fake = Object.new
    room = @room
    bob = @bob
    output = @output
    fake.define_singleton_method(:generate_compiled!) do |_compiled|
      AiRoomContextConsent.find_by!(room: room, user: bob).revoke!
      output
    end
    assert_raises(AiWorkspace::Errors::ConsentRequired) do
      run_answer(factory: ->(_key) { fake })
    end
    assert_equal "settled", AiUsageReservation.sole.state
    assert_equal 20_000_000, AiUsageReservation.sole.actual_ticks
    assert_equal 1, @room.messages.count
  end

  test "provider ambiguity keeps durable reservation uncertain and never retries" do
    grants!
    fake = Object.new
    fake.define_singleton_method(:generate_compiled!) do |_compiled|
      raise AiWorkspace::Providers::XaiResponses::ProviderUnavailable
    end
    assert_raises(AiWorkspace::Errors::ProviderUnavailable) do
      run_answer(factory: ->(_key) { fake })
    end
    assert_equal "uncertain", AiUsageReservation.sole.state
    assert_equal AiWorkspace::PostgresUsageLedger::REQUEST_TICKS,
      AiUsageReservation.sole.allocated_ticks
    assert_equal 1, @room.messages.count
    assert_raises(AiWorkspace::Errors::BudgetExceeded) do
      run_answer(factory: ->(_key) { fake })
    end
  end

  test "unsupported output is billed before it is withheld from the user" do
    grants!
    fake = Object.new
    result = @output.dup
    result.text = "We guarantee delivery tomorrow for $500."
    fake.define_singleton_method(:generate_compiled!) { |_compiled| result }
    assert_raises(AiWorkspace::Errors::ProviderUnavailable) do
      run_answer(factory: ->(_key) { fake })
    end
    assert_equal "settled", AiUsageReservation.sole.state
    assert_equal 20_000_000, AiUsageReservation.sole.actual_ticks
    assert_equal 1, @room.messages.count
  end
end
