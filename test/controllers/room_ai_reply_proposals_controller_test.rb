require "test_helper"

class RoomAiReplyProposalsControllerTest < ActionDispatch::IntegrationTest
  include Devise::Test::IntegrationHelpers

  def setup
    @alice, @bob = users(:one), users(:two)
    @room = Room.create_private_room([@alice, @bob],
      "private_#{[@alice.id, @bob.id].sort.join('_')}")
    @url = room_ai_reply_proposal_path(@room)
    @source = @room.messages.create!(user: @bob,
      body: "Please clarify the Rails signup requirement")
    AiAutomationPolicy.create!(room: @room, user: @alice, reply_mode: "review")
    AiConversationGoal.create!(room: @room, user: @alice, purpose: "Clarify scope")
  end

  def allow_background
    [@alice, @bob].each do |person|
      AiRoomContextConsent.find_or_initialize_by(room: @room, user: person).grant!
      AiRoomAutomationConsent.create!(room: @room, user: person,
        member_set_fingerprint: AiRoomAutomationConsent.fingerprint_for(@room),
        background_context_enabled: true)
    end
  end

  test "explicit offline propose, owner-only Apply and distinct human Send" do
    sign_in @alice
    allow_background
    get @url, as: :json
    assert_response :success
    assert_nil response.parsed_body["proposal"]

    post @url, params: { proposal: { language: "en" } }, as: :json
    assert_response :created
    candidate = response.parsed_body.fetch("proposal")
    assert_equal "offline_template", candidate.fetch("origin")
    assert_equal false, candidate.fetch("ai_assisted")
    assert_equal false, candidate.fetch("provider_called")
    assert_equal false, response.parsed_body.fetch("automatic_send_active")
    assert_equal "private, no-store", response.headers["Cache-Control"]

    patch apply_room_ai_reply_proposal_path(@room, candidate.fetch("id")), as: :json
    assert_response :success
    assert_equal "applied", response.parsed_body.dig("proposal", "state")
    assert_equal false, response.parsed_body.fetch("applied_to_composer")
    assert_equal 1, @room.messages.count
    assert_equal 0, AiUsageReservation.count

    sign_out @alice
    sign_in @bob
    get @url, as: :json
    assert_response :success
    assert_nil response.parsed_body["proposal"]
    patch apply_room_ai_reply_proposal_path(@room, candidate.fetch("id")), as: :json
    assert_response :not_found
  end

  test "authorization, tampered POST, stale source and explicit dismissal" do
    post @url, params: { proposal: { language: "en" } }, as: :json
    assert_response :unauthorized
    sign_in @alice
    post @url, params: { proposal: { language: "en" } }, as: :json
    assert_response :forbidden
    allow_background
    post @url, params: { proposal: { language: "en", body: "fake AI" } }, as: :json
    assert_response :unprocessable_entity
    post @url, params: { proposal: { language: "en" } }, as: :json
    assert_response :created
    id = response.parsed_body.dig("proposal", "id")
    @source.update!(body: "Different requirement")
    patch apply_room_ai_reply_proposal_path(@room, id), as: :json
    assert_response :conflict
    assert_not_includes response.body, "Different requirement"
    assert_equal 0, @room.messages.where(user: @alice).count

    post @url, params: { proposal: { language: "ru" } }, as: :json
    assert_response :created
    latest_id = response.parsed_body.dig("proposal", "id")
    delete dismiss_room_ai_reply_proposal_path(@room, latest_id), as: :json
    assert_response :no_content
    patch apply_room_ai_reply_proposal_path(@room, latest_id), as: :json
    assert_response :conflict
  end
end
