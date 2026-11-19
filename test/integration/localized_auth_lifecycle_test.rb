# frozen_string_literal: true

require "test_helper"

# Exercise the real Devise request flow, not sign_in helpers that bypass forms
# and session creation. SMTP delivery and production signup policy are separate
# acceptance gates and are intentionally not changed here.
class LocalizedAuthLifecycleTest < ActionDispatch::IntegrationTest
  test "registration, sign out, login and profile access preserve all four UI locales" do
    %w[en ru hy es].each do |locale|
      email = "locale-auth-#{locale}@example.test"
      password = "ValidPass-2026-123"

      get new_user_registration_path, params: { ui_locale: locale }
      assert_response :success
      assert_select "html[lang=?]", locale
      assert_select ".sd-auth-heading h1", text: I18n.t("ui.auth.signup_title", locale: locale)

      assert_difference "User.count", 1 do
        post user_registration_path, params: {
          user: {
            email: email,
            display_name: "Tester #{locale.upcase}",
            password: password,
            password_confirmation: password
          }
        }
      end
      assert_response :redirect
      follow_redirect!
      assert_response :success
      assert_select "html[lang=?]", locale
      assert_equal "Tester #{locale.upcase}", User.find_by!(email: email).chat_label

      get edit_user_registration_path
      assert_response :success
      assert_select "html[lang=?]", locale

      delete destroy_user_session_path
      assert_response :redirect

      get new_user_session_path
      assert_response :success
      assert_select "html[lang=?]", locale
      assert_select ".sd-auth-heading h1", text: I18n.t("ui.auth.login_title", locale: locale)

      post user_session_path, params: {
        user: { email: email, password: password }
      }
      assert_response :redirect
      follow_redirect!
      assert_response :success
      assert_select "html[lang=?]", locale

      get edit_user_registration_path
      assert_response :success
      delete destroy_user_session_path
      assert_response :redirect
    end
  end
end
