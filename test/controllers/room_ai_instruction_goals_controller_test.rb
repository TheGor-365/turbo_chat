require "test_helper"

class RoomAiInstructionGoalsControllerTest < ActionDispatch::IntegrationTest
  include Devise::Test::IntegrationHelpers

  def setup
    @alice, @bob = users(:one), users(:two)
    @room = Room.create_private_room([@alice, @bob],
      "private_#{[@alice.id, @bob.id].sort.join('_')}")
    @url = room_ai_instruction_goal_path(@room)
  end

  test "read-only room purpose does not create an extra personal goal or Send" do
    get @url
    assert_response :unauthorized
    sign_in @alice
    get @url
    assert_response :success
    assert_equal false, response.parsed_body.fetch("configured")
    RoomAiInstructionRevision.create!(room: @room, editor: @alice,
      revision_number: 1, content: "Clarify the Rails scope.")
    get @url
    assert_response :success
    assert_equal true, response.parsed_body.fetch("configured")
    assert_equal 1, response.parsed_body.fetch("current_revision")
    assert_equal false, response.parsed_body.fetch("ai_answer_available")
    assert_equal "private, no-store", response.headers.fetch("Cache-Control")
    assert_equal 0, AiConversationGoal.where(room: @room).count
  end

  test "long instruction is not silently truncated for AI" do
    sign_in @alice
    RoomAiInstructionRevision.create!(room: @room, editor: @alice,
      revision_number: 1, content: "A" * 1300)
    get @url
    assert_response :success
    assert_equal false, response.parsed_body.fetch("configured")
    assert_equal 0, response.parsed_body.fetch("current_revision")
  end
end
