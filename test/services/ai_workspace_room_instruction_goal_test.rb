require "test_helper"
require "securerandom"

class AiWorkspaceRoomInstructionGoalTest < ActiveSupport::TestCase
  def setup
    @alice, @bob = users(:one), users(:two)
    @room = Room.create_private_room([@alice, @bob],
      "private_#{[@alice.id, @bob.id].sort.join('_')}")
    @incoming = @room.messages.create!(user: @bob, body: "Can we clarify the feature requirements?")
  end

  def grant_all
    [@alice, @bob].each do |user|
      AiRoomContextConsent.find_or_initialize_by(room: @room, user: user).grant!
    end
  end

  def create_instruction(content, revision = 1)
    RoomAiInstructionRevision.create!(room: @room, editor: @alice,
      content: content, revision_number: revision)
  end

  def request(revision)
    AiWorkspace::GenerationOrchestrator::Request.new(mode: "answer",
      actor: @alice, room: @room, draft_text: "", request_id: SecureRandom.uuid,
      confirmed: "1", expected_goal_revision: revision,
      goal_source: "room_instructions")
  end

  test "existing room instruction alone supplies bounded lower-trust Answer purpose" do
    create_instruction("Clarify requirements before any deadlines.")
    grant_all
    req = request(1)
    plan = AiWorkspace::GenerationOrchestrator.new.prepare(request: req)
    compiled = AiWorkspace::GenerationInputContract.build!(plan: plan, request: req)
    assert_equal "room_instructions", plan.goal_snapshot.fetch(:source)
    assert_equal "Clarify requirements before any deadlines.", plan.goal_snapshot.fetch(:purpose)
    assert_includes compiled.user_content, '"scope":"room_instructions"'
    assert_includes compiled.user_content, "Clarify requirements"
    refute_includes compiled.system_instruction, "Clarify requirements"
    assert_equal 0, AiConversationGoal.where(room: @room).count
    assert_equal 1, @room.messages.count
  end

  test "old room instruction revision is invalid after another saved revision" do
    create_instruction("First agreed instructions.")
    grant_all
    old_request = request(1)
    old_fingerprint = AiWorkspace::GenerationInputContract.build!(
      plan: AiWorkspace::GenerationOrchestrator.new.prepare(request: old_request),
      request: old_request).fingerprint
    create_instruction("Updated agreed instructions.", 2)
    assert_raises(AiWorkspace::Errors::InvalidSelection) do
      AiWorkspace::GenerationOrchestrator.new.prepare(request: old_request)
    end
    new_request = request(2)
    new_fingerprint = AiWorkspace::GenerationInputContract.build!(
      plan: AiWorkspace::GenerationOrchestrator.new.prepare(request: new_request),
      request: new_request).fingerprint
    assert_not_equal old_fingerprint, new_fingerprint
  end

  test "room instructions cannot override missing peer consent" do
    create_instruction("Clarify scope.")
    assert_raises(AiWorkspace::Errors::ConsentRequired) do
      AiWorkspace::GenerationOrchestrator.new.prepare(request: request(1))
    end
  end
end
