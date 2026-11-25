require "test_helper"

class RoomAiSharedWritingPreferencesControllerTest < ActionDispatch::IntegrationTest
  include Devise::Test::IntegrationHelpers

  setup do
    @owner, @member = users(:one), users(:two)
    @room = Room.create!(name: "Shared API test", kind: "private_group", is_private: true, owner: @owner)
    @room.participants.create!(user: @owner, group_role: "owner")
    @room.participants.create!(user: @member, group_role: "member")
    @path = room_ai_shared_writing_preference_path(@room)
    @preference = { profile_id: "universal", writing_style: "polish_clarity", language: "en", tone: "neutral" }
  end

  test "owner writes shared values and member reads but cannot overwrite" do
    sign_in @owner
    assert_no_difference "AiRoomSharedWritingPreference.count" do
      get @path
      assert_response :success
      assert_equal 0, response.parsed_body["revision"]
    end
    patch @path, params: { preference: @preference, expected_revision: 0 }, as: :json
    assert_response :success
    assert_equal 1, response.parsed_body["revision"]
    assert_equal "private, no-store", response.headers["Cache-Control"]
    patch @path, params: { preference: @preference.merge(language: "hy"), expected_revision: 0 }, as: :json
    assert_response :conflict
    sign_out @owner
    sign_in @member
    get @path
    assert_response :success
    assert_equal false, response.parsed_body["editable"]
    assert_equal "en", response.parsed_body["preference"]["language"]
    assert_equal @owner.id, response.parsed_body["editor"]["id"]
    assert_not_includes response.body, @owner.email
    patch @path, params: { preference: @preference, expected_revision: 1 }, as: :json
    assert_response :forbidden
    @room.participants.where(user: @member).delete_all
    get @path
    assert_response :forbidden
  end

  test "strict JSON payload and unrelated identity fields rejected" do
    sign_in @owner
    assert_no_difference "AiRoomSharedWritingPreference.count" do
      patch @path, params: { preference: @preference, expected_revision: 0 }
      assert_response :unsupported_media_type
      patch @path, params: { preference: @preference, expected_revision: "0" }, as: :json
      assert_response :unprocessable_entity
      patch @path, params: { preference: @preference.merge(enabled: true), expected_revision: 0 }, as: :json
      assert_response :unprocessable_entity
      patch @path, params: { preference: @preference, expected_revision: 0, user_id: @member.id }, as: :json
      assert_response :unprocessable_entity
    end
  end

  test "guest outsider and direct conversation cannot read shared defaults" do
    get @path
    assert_redirected_to new_user_session_path
    outsider = User.create!(email: "shared-api-outsider@example.test", password: "password123")
    sign_in outsider
    get @path
    assert_response :forbidden
    patch @path, params: { preference: @preference, expected_revision: 0 }, as: :json
    assert_response :forbidden
    sign_out outsider
    sign_in @owner
    dm = Room.create_private_room([@owner, @member], "private_#{[@owner.id, @member.id].sort.join('_')}")
    get room_ai_shared_writing_preference_path(dm)
    assert_response :forbidden
  end
end
