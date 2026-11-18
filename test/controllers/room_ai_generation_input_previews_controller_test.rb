require "test_helper"

class RoomAiGenerationInputPreviewsControllerTest < ActionDispatch::IntegrationTest
  include Devise::Test::IntegrationHelpers

  def setup
    @alice, @bob = users(:one), users(:two)
    @room = Room.create_private_room([@alice, @bob],
      "private_#{[@alice.id, @bob.id].sort.join('_')}")
    @url = room_ai_generation_input_preview_path(@room)
    @incoming = @room.messages.create!(user: @bob,
      body: "Which Rails signup form needs improvement?")
    AiConversationGoal.create!(room: @room, user: @alice,
      purpose: "Clarify project requirements", revision: 1, active: true)
  end

  def grant_context
    [@alice, @bob].each do |user|
      AiRoomContextConsent.find_or_initialize_by(room: @room, user: user).grant!
    end
  end

  test "only authenticated eligible members can obtain a preview" do
    post @url, params: { preview: { mode: "answer", draft_text: "",
      expected_goal_revision: 1 } }, as: :json
    assert_response :unauthorized
    sign_in @alice
    post room_ai_generation_input_preview_path(99_999_999),
      params: { preview: { mode: "beautify", draft_text: "Fix Rails." } }, as: :json
    assert_response :not_found
  end

  test "answer preview requires consent and current goal, never dispatches provider or Send" do
    sign_in @alice
    payload = { preview: { mode: "answer", draft_text: "",
      expected_goal_revision: 1 } }
    post @url, params: payload, as: :json
    assert_response :unprocessable_entity
    assert_equal "context_consent_required", response.parsed_body.fetch("error")
    grant_context
    post @url, params: payload, as: :json
    assert_response :success
    result = response.parsed_body
    assert_equal "answer", result.fetch("mode")
    assert_equal [@incoming.id], result.fetch("source_ids")
    assert_equal "Clarify project requirements", result.fetch("goal_purpose")
    assert_equal "Which Rails signup form needs improvement?",
      result.fetch("sources").sole.fetch("text")
    assert_equal false, result.fetch("provider_called")
    assert_equal false, result.fetch("budget_reserved")
    assert_equal false, result.fetch("message_sent")
    assert_equal "private, no-store", response.headers["Cache-Control"]
    assert_equal 1, @room.messages.count
    assert_equal 0, AiUsageReservation.count

    AiConversationGoal.find_by!(room: @room, user: @alice).update!(revision: 2)
    post @url, params: payload, as: :json
    assert_response :unprocessable_entity
    assert_equal 0, AiUsageReservation.count
  end

  test "beautify preview contains only author draft without peer consent or spending" do
    sign_in @alice
    post @url, params: { preview: { mode: "beautify",
      draft_text: "pls fix ruby on rails bug." } }, as: :json
    assert_response :success
    result = response.parsed_body
    assert_equal "beautify", result.fetch("mode")
    assert_equal "pls fix ruby on rails bug.", result.fetch("draft_preview")
    assert_equal [], result.fetch("sources")
    assert_not_includes response.body, @incoming.body
    assert_equal 1, @room.messages.count
    assert_equal 0, AiUsageReservation.count
  end

  test "tampered payload, nonempty answer and missing draft are denied" do
    sign_in @alice
    grant_context
    [
      { mode: "auto_reply", draft_text: "" },
      { mode: "answer", draft_text: "Do not replace my draft", expected_goal_revision: 1 },
      { mode: "beautify", draft_text: "" },
      { mode: "beautify", draft_text: "hi", provider: "xai" },
      { mode: "answer", draft_text: "", expected_goal_revision: 999 }
    ].each do |bad|
      post @url, params: { preview: bad }, as: :json
      assert_response :unprocessable_entity
    end
    assert_equal 0, AiUsageReservation.count
    assert_equal 1, @room.messages.count
  end
end
