require "test_helper"

class UsersControllerTest < ActionDispatch::IntegrationTest
  test "private conversation endpoint requires sign in" do
    get user_path(users(:two))
    assert_redirected_to new_user_session_path
  end
end
