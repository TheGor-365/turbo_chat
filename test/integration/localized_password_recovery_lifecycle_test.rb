# frozen_string_literal: true

require "test_helper"
require "uri"
require "nokogiri"

# Exercise the actual Devise email-token recovery lifecycle in the test mailer.
# This does NOT prove production SMTP delivery or authorize public reset.
class LocalizedPasswordRecoveryLifecycleTest < ActionDispatch::IntegrationTest
  test "reset link is localized, single-use and changes only its owner's password" do
    previous_options = Devise.mailer.default_url_options.dup
    Devise.mailer.default_url_options = previous_options.merge(host: "example.test", protocol: "https")

    %w[en ru hy es].each do |locale|
      user = User.create!(
        email: "reset-lifecycle-#{locale}@example.test",
        password: "BeforeReset-2026",
        password_confirmation: "BeforeReset-2026"
      )
      other = users(:two)
      old_other_digest = other.encrypted_password

      get new_user_password_path, params: { ui_locale: locale }
      assert_response :success
      assert_select "html[lang=?]", locale
      assert_select ".sd-auth-heading h1",
        text: I18n.t("ui.auth.forgot_title", locale: locale)

      assert_difference "ActionMailer::Base.deliveries.length", 1 do
        post user_password_path, params: { user: { email: user.email } }
      end
      assert_response :redirect
      mail = ActionMailer::Base.deliveries.last
      assert_equal [user.email], mail.to
      assert_equal I18n.t("devise.mailer.reset_password_instructions.subject", locale: locale), mail.subject

      html = Nokogiri::HTML(mail.body.decoded)
      link = html.at_css("a[href*='reset_password_token']")
      assert link, "#{locale}: reset link missing"
      uri = URI.parse(link["href"])
      assert_equal "example.test", uri.host
      token = URI.decode_www_form(uri.query.to_s).to_h["reset_password_token"]
      assert token.present?, "#{locale}: reset token missing"

      get edit_user_password_path, params: { reset_password_token: token }
      assert_response :success
      assert_select "html[lang=?]", locale
      assert_select ".sd-auth-heading h1",
        text: I18n.t("ui.auth.reset_title", locale: locale)

      new_password = "AfterReset-2026-#{locale}"
      put user_password_path, params: { user: {
        reset_password_token: token,
        password: new_password,
        password_confirmation: new_password
      } }
      assert_response :redirect
      assert user.reload.valid_password?(new_password)
      assert_equal old_other_digest, other.reload.encrypted_password

      # After password change the old email link cannot change it again.
      put user_password_path, params: { user: {
        reset_password_token: token,
        password: "ReplayAttempt-2026",
        password_confirmation: "ReplayAttempt-2026"
      } }
      assert_response :unprocessable_entity
      assert user.reload.valid_password?(new_password)

      delete destroy_user_session_path
      assert_response :redirect
      post user_session_path, params: { user: {
        email: user.email, password: new_password
      } }
      assert_response :redirect
      delete destroy_user_session_path
      assert_response :redirect
    end
  ensure
    Devise.mailer.default_url_options = previous_options if previous_options
  end
end
