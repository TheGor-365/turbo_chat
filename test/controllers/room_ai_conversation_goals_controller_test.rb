require "test_helper"

class RoomAiConversationGoalsControllerTest < ActionDispatch::IntegrationTest
  include Devise::Test::IntegrationHelpers

  def setup
    @alice, @bob = users(:one), users(:two)
    @room = Room.create_private_room([@alice, @bob],
      "private_#{[@alice.id, @bob.id].sort.join('_')}")
    @url = room_ai_conversation_goal_path(@room)
  end

  def goal(purpose: "Discuss a Rails feature", base_revision: 0)
    { goal: { purpose: purpose, constraints: "Do not promise pricing",
      desired_outcome: "Agree on next steps", base_revision: base_revision } }
  end

  test "personal goal stays private per user and does not activate AI or send" do
    get @url, as: :json
    assert_response :unauthorized

    sign_in @alice
    get @url, as: :json
    assert_response :success
    assert_equal false, response.parsed_body.fetch("configured")
    assert_equal 0, response.parsed_body.fetch("current_revision")
    assert_equal "private, no-store", response.headers["Cache-Control"]

    patch @url, params: goal, as: :json
    assert_response :success
    assert_equal true, response.parsed_body.fetch("configured")
    assert_equal false, response.parsed_body.fetch("ai_answer_available")
    assert_equal 1, response.parsed_body.fetch("current_revision")
    assert_equal 1, AiConversationGoal.count
    assert_equal 0, @room.messages.count
    assert_equal 0, AiRoomContextConsent.where(room: @room).count

    sign_out @alice
    sign_in @bob
    get @url, as: :json
    assert_response :success
    assert_nil response.parsed_body.fetch("goal")
    assert_equal false, response.parsed_body.fetch("configured")
    patch @url, params: goal(purpose: "Different private goal"), as: :json
    assert_response :success
    assert_equal 2, AiConversationGoal.where(room: @room).count

    sign_out @bob
    sign_in @alice
    get @url, as: :json
    assert_equal "Discuss a Rails feature", response.parsed_body.dig("goal", "purpose")
    assert_equal 0, @room.messages.count
  end

  test "revisions reject stale writes without losing the latest human goal" do
    sign_in @alice
    patch @url, params: goal, as: :json
    assert_response :success
    patch @url, params: goal(purpose: "New goal", base_revision: 0), as: :json
    assert_response :conflict
    assert_equal 1, response.parsed_body.fetch("current_revision")
    patch @url, params: goal(purpose: "New goal", base_revision: 1), as: :json
    assert_response :success
    assert_equal 2, response.parsed_body.fetch("current_revision")
    assert_equal "New goal", AiConversationGoal.find_by!(room: @room, user: @alice).purpose
    patch @url, params: goal(purpose: "New goal", base_revision: 2), as: :json
    assert_response :success
    assert_equal false, response.parsed_body.fetch("changed")
    assert_equal 2, response.parsed_body.fetch("current_revision")
  end

  test "revoking and reactivating changes revision but no shared consent" do
    sign_in @alice
    patch @url, params: goal, as: :json
    assert_response :success
    delete @url, params: { goal: { base_revision: 0 } }, as: :json
    assert_response :conflict
    delete @url, params: { goal: { base_revision: 1 } }, as: :json
    assert_response :success
    assert_equal false, response.parsed_body.fetch("configured")
    assert_equal 2, response.parsed_body.fetch("current_revision")
    assert_equal false, AiConversationGoal.find_by!(room: @room, user: @alice).active?
    patch @url, params: goal(purpose: "Renewed goal", base_revision: 2), as: :json
    assert_response :success
    assert_equal 3, response.parsed_body.fetch("current_revision")
    assert_equal "Renewed goal", AiConversationGoal.find_by!(room: @room, user: @alice).purpose
    assert_equal 0, @room.messages.count
    assert_equal 0, AiRoomContextConsent.where(room: @room).count
  end

  test "outside member and public room cannot read or set personal goals" do
    outsider = User.create!(email: "goal-outsider@example.test", password: "test-password-123")
    sign_in outsider
    get @url, as: :json
    assert_response :forbidden
    patch @url, params: goal, as: :json
    assert_response :forbidden
    sign_out outsider
    sign_in @alice
    public_room = Room.create!(name: "PublicGoalsTest", kind: "public_room", is_private: false)
    public_room.joinables.create!(user: @alice)
    get room_ai_conversation_goal_path(public_room), as: :json
    assert_response :forbidden
    patch room_ai_conversation_goal_path(public_room), params: goal, as: :json
    assert_response :forbidden
    assert_equal 0, AiConversationGoal.count

    @room.participants.where(user: @alice).delete_all
    get @url, as: :json
    assert_response :forbidden
    assert_equal 0, AiConversationGoal.count
  end

  test "unexpected fields, secrets, controls, lengths and invalid revisions are rejected" do
    sign_in @alice
    invalid = [
      { goal: { purpose: "Hello", constraints: "", desired_outcome: "", base_revision: 0,
        allow_auto_reply: true } },
      goal(purpose: "x" * 501),
      goal(purpose: "xai-#{'A' * 24}"),
      goal(purpose: "bad\u202Egoal"),
      goal(purpose: ""),
      goal.merge(goal: goal.fetch(:goal).except(:base_revision)),
      { goal: { purpose: ["array"], constraints: "", desired_outcome: "", base_revision: 0 } },
      goal(base_revision: "-1"), goal(base_revision: "NaN")
    ]
    invalid.each do |payload|
      patch @url, params: payload, as: :json
      assert_response :unprocessable_entity
    end
    assert_equal 0, AiConversationGoal.count
    assert_equal 0, @room.messages.count
  end
end
