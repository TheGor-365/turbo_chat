require "test_helper"

class RoomAiContextConsentsControllerTest < ActionDispatch::IntegrationTest
  include Devise::Test::IntegrationHelpers

  def setup
    @alice, @bob = users(:one), users(:two)
    @room = Room.create_private_room([@alice, @bob],
      "private_#{[@alice.id, @bob.id].sort.join('_')}")
  end

  test "each participant can opt in and revoke only their own contribution" do
    sign_in @alice
    patch room_ai_context_consent_path(@room), params: { consent: { enabled: "1" } }
    assert_response :success
    assert_equal true, response.parsed_body.fetch("enabled")
    assert_equal false, response.parsed_body.fetch("ready")
    assert_equal 1, response.parsed_body.fetch("granted")
    assert_equal 1, AiRoomContextConsent.where(room: @room).count
    assert_not AiRoomContextConsent.enabled_for?(room: @room, user: @bob)
    sign_out @alice

    sign_in @bob
    patch room_ai_context_consent_path(@room), params: { consent: { enabled: "1" } }
    assert_response :success
    assert_equal true, response.parsed_body.fetch("ready")
    sign_out @bob

    sign_in @alice
    get room_ai_context_consent_path(@room)
    assert_response :success
    assert_equal true, response.parsed_body.fetch("ready")
    patch room_ai_context_consent_path(@room), params: { consent: { enabled: "0" } }
    assert_response :success
    assert_equal false, response.parsed_body.fetch("enabled")
    assert_equal false, response.parsed_body.fetch("ready")
    assert_not AiRoomContextConsent.enabled_for?(room: @room, user: @alice)
    assert_equal "no-store", response.headers["Cache-Control"].split(", ").last
  end

  test "single member private group returns actionable status and cannot grant consent" do
    room = Room.create!(name: "Solo private group", kind: "private_group",
      is_private: true, owner: @alice)
    room.participants.create!(user: @alice, group_role: "owner")
    sign_in @alice

    get room_ai_context_consent_path(room)
    assert_response :success
    assert_equal "not_enough_members", response.parsed_body.fetch("reason")
    assert_equal 1, response.parsed_body.fetch("members")
    assert_equal false, response.parsed_body.fetch("available")
    assert_equal false, response.parsed_body.fetch("ready")

    patch room_ai_context_consent_path(room), params: { consent: { enabled: "1" } }
    assert_response :unprocessable_entity
    assert_equal "not_enough_members", response.parsed_body.fetch("reason")
    assert_equal 0, AiRoomContextConsent.where(room: room).count
  end

  test "forged grants and nonmembers cannot opt in" do
    outsider = User.create!(email: "h3g-outsider@example.test", password: "secure-password")
    sign_in outsider
    patch room_ai_context_consent_path(@room), params: { consent: { enabled: "1", user_id: @alice.id } }
    assert_response :forbidden
    assert_equal 0, AiRoomContextConsent.where(room: @room).count
    sign_out outsider

    sign_in @alice
    patch room_ai_context_consent_path(@room), params: { consent: { enabled: "true" } }
    assert_response :unprocessable_entity
    assert_equal 0, AiRoomContextConsent.where(room: @room).count
    room = Room.create!(name: "Public no context grants")
    room.joinables.create!(user: @alice)
    patch room_ai_context_consent_path(room), params: { consent: { enabled: "1" } }
    assert_response :forbidden
  end
end
