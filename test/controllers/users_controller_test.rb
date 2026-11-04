require "test_helper"

class UsersControllerTest < ActionDispatch::IntegrationTest
  test "valid credentials create a real Devise HTTP login session" do
    post user_session_path, params: {
      user: { email: users(:one).email, password: "test-password-123" }
    }

    assert_response :redirect
    get rooms_path
    assert_response :success
  end

  test "private conversation creation requires sign in" do
    assert_no_difference "Room.count" do
      post start_user_conversation_path(users(:two))
    end
    assert_redirected_to new_user_session_path
  end

  test "GET requests cannot create a private conversation" do
    sign_in users(:one)
    assert_no_difference "Room.count" do
      assert_raises(ActionController::RoutingError) do
        Rails.application.routes.recognize_path("/user/#{users(:two).id}", method: :get)
      end
    end
  end

  test "POST creates exactly one private conversation between two accounts" do
    sign_in users(:one)
    assert_difference "Room.count", 1 do
      post start_user_conversation_path(users(:two))
    end
    assert_response :see_other

    room = Room.find_by!(name: "private_#{[users(:one).id, users(:two).id].sort.join('_')}")
    assert_redirected_to room_path(room)
    assert room.is_private?
    assert_equal [users(:one).id, users(:two).id].sort, room.participants.pluck(:user_id).sort

    assert_no_difference "Room.count" do
      post start_user_conversation_path(users(:two))
    end
    assert_response :see_other
    assert_equal 2, room.participants.count
  end

  test "self conversation does not create a room" do
    sign_in users(:one)
    assert_no_difference "Room.count" do
      post start_user_conversation_path(users(:one))
    end
    assert_redirected_to rooms_path
  end
end
