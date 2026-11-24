require "test_helper"
require "securerandom"

class AiWorkspaceSyntheticAnswerTest < ActiveSupport::TestCase
  def setup
    @alice, @bob = users(:one), users(:two)
    @room = Room.create_private_room([@alice, @bob],
      "private_#{[@alice.id, @bob.id].sort.join('_')}")
    @room.messages.create!(user: @bob,
      body: "POST /orders gives 422; please find out why. Deadlines and budget are not approved.")
    RoomAiInstructionRevision.create!(room: @room, editor: @alice,
      revision_number: 1, content: "Ask for facts; do not invent commitments.")
    @id = SecureRandom.uuid
    @ledger = Object.new
    @ledger.define_singleton_method(:reserve!) do |**_args|
      raise "Synthetic mode must never reserve real money"
    end
    @factory = ->(_key) { raise "Synthetic mode must never create a network provider" }
  end

  def grants!
    [@alice, @bob].each do |person|
      AiRoomContextConsent.find_or_initialize_by(room: @room, user: person).grant!
    end
  end

  def demo(revision: 1)
    service = AiWorkspace::AnswerGeneration.new(ledger: @ledger,
      provider_factory: @factory)
    AiWorkspace::AnswerGeneration.stub(:enabled?, true) do
      AiWorkspace::AnswerGeneration.stub(:synthetic_enabled?, true) do
        service.call(actor: @alice, room: @room, request_id: @id,
          expected_goal_revision: revision, confirmed: "1", draft_text: "")
      end
    end
  end

  test "synthetic Answer uses approved source, returns zero-cost signed candidate and never calls network or ledger" do
    grants!
    before = @room.messages.count
    result = demo
    assert_equal true, result.synthetic
    assert_equal 0, result.cost_ticks
    assert_equal "synthetic-local-no-ai", result.model
    assert_includes result.text, "СИНТЕТИЧЕСКИЙ ТЕСТ"
    assert_includes result.text, "POST /orders"
    assert_includes result.text, "422"
    assert_equal [@room.messages.first.id], result.source_ids
    assert_equal 1, result.goal_revision
    assert_match(/\A[0-9a-f]{64}\z/, result.fingerprint)
    assert_equal 0, AiUsageReservation.count
    assert_equal before, @room.messages.count

    token = AiWorkspace::DraftProvenance.issue(actor: @alice, room: @room,
      source_text: result.text, answer_context: {
        "request_id" => result.request_id,
        "goal_revision" => result.goal_revision,
        "fingerprint" => result.fingerprint
      })
    assert AiWorkspace::DraftProvenance.valid?(token: token,
      actor: @alice, room: @room, source_text: result.text)
    AiRoomContextConsent.find_by!(room: @room, user: @bob).revoke!
    refute AiWorkspace::DraftProvenance.valid?(token: token,
      actor: @alice, room: @room, source_text: result.text)
  end

  test "missing grants and stale saved instructions fail before synthetic output" do
    assert_raises(AiWorkspace::Errors::InvalidSelection) { demo }
    grants!
    assert_raises(AiWorkspace::Errors::InvalidSelection) { demo(revision: 2) }
    assert_equal 0, AiUsageReservation.count
    assert_equal 1, @room.messages.count
  end

  test "synthetic and paid flags are mutually exclusive and production cannot enable either" do
    original_mock = ENV["TURBO_CHAT_AI_ANSWER_SYNTHETIC"]
    original_live = ENV["XAI_ANSWER_GENERATION_ENABLED"]
    original_key = ENV["XAI_API_KEY"]
    ENV["TURBO_CHAT_AI_ANSWER_SYNTHETIC"] = "1"
    ENV["XAI_ANSWER_GENERATION_ENABLED"] = "1"
    ENV["XAI_API_KEY"] = "xai-test-only-not-a-real-key"
    Rails.env.stub(:development?, true) do
      refute AiWorkspace::AnswerGeneration.synthetic_enabled?
      refute AiWorkspace::AnswerGeneration.live_enabled?
      refute AiWorkspace::AnswerGeneration.enabled?
    end
    Rails.env.stub(:development?, false) do
      refute AiWorkspace::AnswerGeneration.synthetic_enabled?
      refute AiWorkspace::AnswerGeneration.live_enabled?
    end
  ensure
    original_mock.nil? ? ENV.delete("TURBO_CHAT_AI_ANSWER_SYNTHETIC") : ENV["TURBO_CHAT_AI_ANSWER_SYNTHETIC"] = original_mock
    original_live.nil? ? ENV.delete("XAI_ANSWER_GENERATION_ENABLED") : ENV["XAI_ANSWER_GENERATION_ENABLED"] = original_live
    original_key.nil? ? ENV.delete("XAI_API_KEY") : ENV["XAI_API_KEY"] = original_key
  end
end
