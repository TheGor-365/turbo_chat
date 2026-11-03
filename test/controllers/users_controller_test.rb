require "test_helper"

class UsersControllerTest < ActionDispatch::IntegrationTest
  include Devise::Test::IntegrationHelpers

  test "guest cannot open or create a conversation" do
    get user_path(users(:two))
    assert_redirected_to new_user_session_path
    assert_no_difference "Room.count" do
      post start_user_conversation_path(users(:two))
    end
    assert_redirected_to new_user_session_path
  end

  test "GET user profile does not create a direct message" do
    sign_in users(:one)
    assert_no_difference "Room.count" do
      get user_path(users(:two))
    end
    assert_response :success
  end

  test "POST begins one private room with both members and subsequent POST is idempotent" do
    sign_in users(:one)
    assert_difference "Room.count", 1 do
      post start_user_conversation_path(users(:two))
    end
    assert_response :see_other
    assert_no_difference "Room.count" do
      post start_user_conversation_path(users(:two))
    end
    room = Room.find_by!(name: "private_#{[users(:one).id, users(:two).id].sort.join('_')}")
    assert room.accessible_to?(users(:one))
    assert room.accessible_to?(users(:two))
    refute room.accessible_to?(users(:admin))
  end
end
