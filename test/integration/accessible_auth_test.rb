require "test_helper"

class AccessibleAuthTest < ActionDispatch::IntegrationTest
  test "guest entry and authentication forms expose a working skip-to-content target" do
    [root_path, new_user_session_path, new_user_registration_path, new_user_password_path].each do |path|
      get path

      assert_response :success
      assert_select "body > a.sd-skip-link[href='#main-content']", text: "Skip to content"
      assert_select "main#main-content[tabindex='-1']", count: 1
    end
  end

  test "signup validation exposes a named error alert associated with invalid input" do
    post user_registration_path, params: {
      user: {
        email: users(:one).email,
        password: "test-password-123",
        password_confirmation: "test-password-123"
      }
    }

    assert_response :unprocessable_entity
    assert_select "#error_explanation[role='alert'][aria-labelledby='auth-error-title']", count: 1
    assert_select "#error_explanation h2#auth-error-title", count: 1
    assert_select "input#user_email[aria-invalid='true'][aria-describedby='error_explanation']", count: 1
    assert_select "input#user_password[autocomplete='new-password']", count: 1
    assert_select "main#main-content", count: 1
  end
end
