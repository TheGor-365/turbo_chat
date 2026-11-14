require "test_helper"
require "minitest/mock"

class DemoAccessPolicyTest < ActionDispatch::IntegrationTest
  include Devise::Test::IntegrationHelpers

  test "R1 production policy has no flag override and development flows stay available" do
    assert_not DemoAccessPolicy.signup_available?(environment: "production")
    assert_not DemoAccessPolicy.password_recovery_available?(environment: "production")
    assert DemoAccessPolicy.signup_available?(environment: "development")
    assert DemoAccessPolicy.password_recovery_available?(environment: "test")
    assert_not DemoAccessPolicy.signup_available?(environment: "production")
  end

  test "closed self-registration denies GET and direct POST without creating users" do
    DemoAccessPolicy.stub(:signup_available?, false) do
      get root_path
      assert_response :success
      assert_select "main a[href=?]", new_user_registration_path, count: 0
      assert_select "main", text: /Controlled-access preview/

      get new_user_session_path
      assert_response :success
      assert_select "a[href=?]", new_user_registration_path, count: 0

      assert_no_difference "User.count" do
        get new_user_registration_path
        assert_response :not_found

        post user_registration_path, params: { user: {
          email: "unauthorized-ci-signup@example.test",
          password: "StrongTestPassword123!",
          password_confirmation: "StrongTestPassword123!"
        } }
        assert_response :not_found
      end

      sign_in users(:one)
      get edit_user_registration_path
      assert_response :success
    end
  end

  test "closed email recovery denies GET, POST and previously issued token routes" do
    DemoAccessPolicy.stub(:password_recovery_available?, false) do
      get new_user_session_path
      assert_response :success
      assert_select "a[href=?]", new_user_password_path, count: 0

      user = users(:one)
      original_token = user.reset_password_token
      get new_user_password_path
      assert_response :not_found

      post user_password_path, params: { user: { email: user.email } }
      assert_response :not_found
      assert_equal original_token, user.reload.reset_password_token

      get edit_user_password_path, params: { reset_password_token: "untrusted-token" }
      assert_response :not_found

      put user_password_path, params: { user: {
        reset_password_token: "untrusted-token",
        password: "ChangedPassword123!",
        password_confirmation: "ChangedPassword123!"
      } }
      assert_response :not_found
    end
  end

  test "normal local Devise signup and reset request forms remain visible" do
    assert DemoAccessPolicy.signup_available?
    assert DemoAccessPolicy.password_recovery_available?
    get new_user_registration_path
    assert_response :success
    get new_user_password_path
    assert_response :success
  end
end
