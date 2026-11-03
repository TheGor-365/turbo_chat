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

  test "private conversation endpoint requires sign in" do
    get user_path(users(:two))
    assert_redirected_to new_user_session_path
  end
end
