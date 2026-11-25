require "test_helper"

class RoomAiMemberEnablementsControllerTest < ActionDispatch::IntegrationTest
  include Devise::Test::IntegrationHelpers

  setup do
    @alice, @bob = users(:one), users(:two)
    @outsider = User.create!(email: "ai-status-outsider@example.test", password: "test-password-123")
    @room = Room.create_private_room([@alice, @bob],
      "private_#{[@alice.id, @bob.id].sort.join('_')}")
  end

  test "private peers see only current personal preference indicators without writes" do
    AiWorkspace::PersonalEnablement.write(actor: @bob, enabled: false, expected_revision: 0)
    AiWorkspace::PersonalEnablement.write(actor: @outsider, enabled: true, expected_revision: 0)
    sign_in @alice
    assert_no_difference ["AiPersonalEnablement.count", "AiUsageReservation.count", "Message.count", "AiRoomContextConsent.count"] do
      get room_ai_member_enablements_path(@room), as: :json
      assert_response :success
    end
    assert_equal "private, no-store", response.headers["Cache-Control"]
    expected = [
      {"user_id" => @alice.id, "enabled" => true, "configured" => false},
      {"user_id" => @bob.id, "enabled" => false, "configured" => true}
    ].sort_by { |entry| entry.fetch("user_id") }
    assert_equal({"members" => expected}, response.parsed_body)
    sign_out @alice
    sign_in @bob
    get room_ai_member_enablements_path(@room), as: :json
    assert_response :success
    assert_equal({"members" => expected}, response.parsed_body)
  end

  test "anonymous outsider and departed member cannot read indicators" do
    get room_ai_member_enablements_path(@room), as: :json
    assert_response :unauthorized
    sign_in @outsider
    get room_ai_member_enablements_path(@room), as: :json
    assert_response :not_found
    sign_out @outsider
    sign_in @bob
    @room.participants.where(user: @bob).delete_all
    get room_ai_member_enablements_path(@room), as: :json
    assert_response :not_found
  end

  test "private group snapshots include current members only and owner cannot write peer settings" do
    group = Room.create!(name: "AI member status group", kind: "private_group",
      is_private: true, owner: @alice)
    group.participants.create!(user: @alice, group_role: "owner")
    group.participants.create!(user: @bob, group_role: "member")
    AiWorkspace::PersonalEnablement.write(actor: @bob, enabled: false, expected_revision: 0)
    sign_in @alice
    get room_ai_member_enablements_path(group), as: :json
    assert_response :success
    assert_equal [@alice.id, @bob.id].sort, response.parsed_body.fetch("members").map { |m| m.fetch("user_id") }
    patch account_ai_enablement_path, params: {user_id: @bob.id, enabled: true, expected_revision: 1}, as: :json
    assert_response :unprocessable_entity
    refute AiPersonalEnablement.find_by!(user: @bob).enabled
    group.participants.where(user: @bob).delete_all
    get room_ai_member_enablements_path(group), as: :json
    assert_response :success
    assert_equal [@alice.id], response.parsed_body.fetch("members").map { |m| m.fetch("user_id") }
  end

  test "public rooms never expose account AI settings" do
    room = Room.create!(name: "Public AI status test", kind: "public_room", is_private: false)
    room.joinables.create!(user: @alice)
    sign_in @alice
    get room_ai_member_enablements_path(room), as: :json
    assert_response :not_found
  end
end
